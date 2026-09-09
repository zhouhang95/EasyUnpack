import Foundation

struct TARArchiveExtractor: ArchiveExtractor {
    nonisolated let format: ArchiveFormat = .tar

    nonisolated func canHandle(_ urls: [URL]) -> Bool {
        urls.count == 1 && ArchiveFormatDetector.detect(urls[0]) == .tar
    }

    nonisolated func extract(_ request: ArchiveRequest) async throws -> ArchiveResult {
        try await Task.detached(priority: .userInitiated) {
            try extractSynchronously(request)
        }.value
    }

    nonisolated private func extractSynchronously(_ request: ArchiveRequest) throws -> ArchiveResult {
        guard let source = request.sourceURLs.first else { throw ArchiveError.noSource }
        let scoped = [source, request.destinationURL]
        let accessed = scoped.map { $0.startAccessingSecurityScopedResource() }
        defer {
            for (url, didAccess) in zip(scoped, accessed) where didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let entries = try readEntries(from: source)
        let roots = Set(entries.compactMap { safeComponents($0.path)?.first })
            .subtracting(["__MACOSX"])
        let destination = roots.count > 1
            ? request.destinationURL.appendingPathComponent(source.deletingPathExtension().lastPathComponent, isDirectory: true)
            : request.destinationURL
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try unpack(entries, from: source, to: destination, progress: request.progress)

        let metadata = destination.appendingPathComponent("__MACOSX", isDirectory: true)
        if FileManager.default.fileExists(atPath: metadata.path) {
            try FileManager.default.removeItem(at: metadata)
        }
        request.progress?(1)
        return ArchiveResult(
            destinationURL: destination,
            format: format,
            topLevelURLs: roots.map { destination.appendingPathComponent($0) }
        )
    }

    nonisolated private struct Entry: Sendable {
        let path: String
        let linkPath: String
        let type: UInt8
        let size: UInt64
        let dataOffset: UInt64
        let permissions: Int
        let modificationTime: TimeInterval
    }

    nonisolated private func readEntries(from source: URL) throws -> [Entry] {
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let archiveSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)

        var entries: [Entry] = []
        var offset: UInt64 = 0
        var pendingPath: String?
        while offset + 512 <= archiveSize {
            try handle.seek(toOffset: offset)
            guard let header = try handle.read(upToCount: 512), header.count == 512 else {
                throw ArchiveError.damagedArchive
            }
            if header.allSatisfy({ $0 == 0 }) { break }

            let type = header[156]
            let size = try tarNumber(header[124..<136])
            let name = string(header[0..<100])
            let prefix = string(header[345..<500])
            let headerPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            let linkPath = string(header[157..<257])
            let dataOffset = offset + 512

            if type == 76 { // GNU long name
                pendingPath = try readStringPayload(handle, offset: dataOffset, size: size)
            } else if type == 120 || type == 103 { // POSIX PAX extended/global header
                let pax = try readStringPayload(handle, offset: dataOffset, size: size)
                if let path = paxValue("path", in: pax) { pendingPath = path }
            } else {
                entries.append(Entry(
                    path: pendingPath ?? headerPath,
                    linkPath: linkPath,
                    type: type,
                    size: size,
                    dataOffset: dataOffset,
                    permissions: Int(try tarNumber(header[100..<108]) & 0o7777),
                    modificationTime: TimeInterval(try tarNumber(header[136..<148]))
                ))
                pendingPath = nil
            }
            let padded = (size + 511) & ~UInt64(511)
            guard dataOffset <= archiveSize, padded <= archiveSize - dataOffset else {
                throw ArchiveError.damagedArchive
            }
            offset = dataOffset + padded
        }
        return entries
    }

    nonisolated private func unpack(
        _ entries: [Entry], from source: URL, to destination: URL,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let total = max(entries.reduce(UInt64(0)) { $0 + $1.size }, 1)
        var completed: UInt64 = 0

        for entry in entries {
            guard let components = safeComponents(entry.path) else {
                throw ArchiveError.extractionFailed("TAR 包含不安全的文件路径：\(entry.path)")
            }
            guard components.first != "__MACOSX" else {
                completed += entry.size
                continue
            }
            let target = components.reduce(destination) { $0.appendingPathComponent($1) }
            let parent = target.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            switch entry.type {
            case 0, 48, 55: // regular file / contiguous file
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                FileManager.default.createFile(atPath: target.path, contents: nil)
                let output = try FileHandle(forWritingTo: target)
                defer { try? output.close() }
                try input.seek(toOffset: entry.dataOffset)
                var remaining = entry.size
                while remaining > 0 {
                    let count = Int(min(remaining, 256 * 1024))
                    guard let chunk = try input.read(upToCount: count), !chunk.isEmpty else {
                        throw ArchiveError.damagedArchive
                    }
                    try output.write(contentsOf: chunk)
                    remaining -= UInt64(chunk.count)
                    progress?(min(Double(completed + entry.size - remaining) / Double(total), 0.99))
                }
            case 53: // directory
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            case 50: // symbolic link, only when the resolved target stays inside the extraction root
                let resolved = parent.appendingPathComponent(entry.linkPath).standardizedFileURL
                guard resolved.path == destination.standardizedFileURL.path ||
                        resolved.path.hasPrefix(destination.standardizedFileURL.path + "/") else {
                    throw ArchiveError.extractionFailed("TAR 包含指向解压目录外部的符号链接：\(entry.path)")
                }
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: entry.linkPath)
            case 49: // hard link; TAR link paths are relative to the archive root
                guard let linkComponents = safeComponents(entry.linkPath) else {
                    throw ArchiveError.extractionFailed("TAR 包含不安全的硬链接：\(entry.path)")
                }
                let linkSource = linkComponents.reduce(destination) { $0.appendingPathComponent($1) }
                guard FileManager.default.fileExists(atPath: linkSource.path) else {
                    throw ArchiveError.extractionFailed("TAR 硬链接目标不存在：\(entry.linkPath)")
                }
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.linkItem(at: linkSource, to: target)
            default:
                break
            }
            completed += entry.size
            progress?(min(Double(completed) / Double(total), 0.99))
            try? FileManager.default.setAttributes([
                .posixPermissions: entry.permissions,
                .modificationDate: Date(timeIntervalSince1970: entry.modificationTime)
            ], ofItemAtPath: target.path)
        }
    }

    nonisolated private func safeComponents(_ path: String) -> [String]? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { return nil }
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        return parts
    }

    nonisolated private func string(_ bytes: Data.SubSequence) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    nonisolated private func tarNumber(_ bytes: Data.SubSequence) throws -> UInt64 {
        let values = Array(bytes)
        guard let first = values.first else { return 0 }
        if first & 0x80 != 0 {
            return values.enumerated().reduce(UInt64(0)) { result, item in
                result << 8 | UInt64(item.offset == 0 ? item.element & 0x7f : item.element)
            }
        }
        let text = String(decoding: values, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        guard text.isEmpty || text.allSatisfy({ $0 >= "0" && $0 <= "7" }),
              let value = UInt64(text.isEmpty ? "0" : text, radix: 8) else {
            throw ArchiveError.damagedArchive
        }
        return value
    }

    nonisolated private func readStringPayload(_ handle: FileHandle, offset: UInt64, size: UInt64) throws -> String {
        guard size <= UInt64(Int.max) else { throw ArchiveError.damagedArchive }
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: Int(size)), data.count == Int(size) else {
            throw ArchiveError.damagedArchive
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0\n"))
    }

    nonisolated private func paxValue(_ key: String, in payload: String) -> String? {
        for record in payload.split(separator: "\n") {
            guard let space = record.firstIndex(of: " "), let equals = record[space...].firstIndex(of: "=") else { continue }
            if record[record.index(after: space)..<equals] == key {
                return String(record[record.index(after: equals)...])
            }
        }
        return nil
    }
}
