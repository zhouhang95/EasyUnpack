import Foundation
import CoreFoundation
import Darwin
import ZipArchive

@_silgen_name("mz_zip_reader_create")
nonisolated private func mzZipReaderCreate(_ handle: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> UnsafeMutableRawPointer?
@_silgen_name("mz_zip_reader_delete")
nonisolated private func mzZipReaderDelete(_ handle: UnsafeMutablePointer<UnsafeMutableRawPointer?>)
@_silgen_name("mz_zip_reader_open_file")
nonisolated private func mzZipReaderOpenFile(_ handle: UnsafeMutableRawPointer?, _ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("mz_zip_reader_set_password")
nonisolated private func mzZipReaderSetPassword(_ handle: UnsafeMutableRawPointer?, _ password: UnsafePointer<CChar>)
@_silgen_name("mz_zip_reader_set_encoding")
nonisolated private func mzZipReaderSetEncoding(_ handle: UnsafeMutableRawPointer?, _ encoding: Int32)
@_silgen_name("mz_zip_reader_save_all")
nonisolated private func mzZipReaderSaveAll(_ handle: UnsafeMutableRawPointer?, _ destination: UnsafePointer<CChar>) -> Int32
@_silgen_name("mz_zip_reader_goto_first_entry")
nonisolated private func mzZipReaderGotoFirstEntry(_ handle: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("mz_zip_reader_goto_next_entry")
nonisolated private func mzZipReaderGotoNextEntry(_ handle: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("mz_zip_reader_entry_save_file")
nonisolated private func mzZipReaderEntrySaveFile(
    _ handle: UnsafeMutableRawPointer?, _ path: UnsafePointer<CChar>
) -> Int32
@_silgen_name("mz_zip_reader_close")
nonisolated private func mzZipReaderClose(_ handle: UnsafeMutableRawPointer?) -> Int32
private typealias MinizipProgressCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int64
) -> Int32
@_silgen_name("mz_zip_reader_set_progress_cb")
nonisolated private func mzZipReaderSetProgressCallback(
    _ handle: UnsafeMutableRawPointer?, _ userdata: UnsafeMutableRawPointer?, _ callback: MinizipProgressCallback?
)
@_silgen_name("mz_zip_reader_set_progress_interval")
nonisolated private func mzZipReaderSetProgressInterval(_ handle: UnsafeMutableRawPointer?, _ milliseconds: UInt32)
@_silgen_name("unzOpen64")
nonisolated private func unzOpen64(_ path: UnsafeRawPointer?) -> UnsafeMutableRawPointer?
@_silgen_name("unzOpen2_64")
nonisolated private func unzOpen2_64(
    _ path: UnsafeRawPointer?, _ fileFunctions: UnsafeMutableRawPointer?
) -> UnsafeMutableRawPointer?
@_silgen_name("unzClose")
nonisolated private func unzClose(_ handle: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("unzGoToFirstFile")
nonisolated private func unzGoToFirstFile(_ handle: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("unzGoToNextFile")
nonisolated private func unzGoToNextFile(_ handle: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("unzGetCurrentFileInfo64")
nonisolated private func unzGetCurrentFileInfo64(
    _ handle: UnsafeMutableRawPointer?, _ info: UnsafeMutableRawPointer?,
    _ filename: UnsafeMutablePointer<CChar>?, _ filenameSize: UInt,
    _ extra: UnsafeMutableRawPointer?, _ extraSize: UInt,
    _ comment: UnsafeMutablePointer<CChar>?, _ commentSize: UInt
) -> Int32
@_silgen_name("unzOpenCurrentFilePassword")
nonisolated private func unzOpenCurrentFilePassword(
    _ handle: UnsafeMutableRawPointer?, _ password: UnsafePointer<CChar>?
) -> Int32
@_silgen_name("unzReadCurrentFile")
nonisolated private func unzReadCurrentFile(
    _ handle: UnsafeMutableRawPointer?, _ buffer: UnsafeMutableRawPointer?, _ length: UInt32
) -> Int32
@_silgen_name("unzCloseCurrentFile")
nonisolated private func unzCloseCurrentFile(_ handle: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("crc32")
nonisolated private func zlibCRC32(
    _ crc: UInt, _ buffer: UnsafePointer<UInt8>?, _ length: UInt32
) -> UInt

nonisolated private final class MinizipProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private let total: Int64
    private let report: @Sendable (Double) -> Void
    private var completed: Int64 = 0
    private var lastPosition: Int64 = 0

    init(total: Int64, report: @escaping @Sendable (Double) -> Void) {
        self.total = max(total, 1)
        self.report = report
    }

    func update(position: Int64) {
        lock.lock()
        if position < lastPosition { completed += lastPosition }
        lastPosition = position
        let value = min(max(Double(completed + position) / Double(total), 0), 0.99)
        lock.unlock()
        report(value)
    }
}

nonisolated private let minizipProgressCallback: MinizipProgressCallback = { _, userdata, _, position in
    guard let userdata else { return 0 }
    Unmanaged<MinizipProgressBox>.fromOpaque(userdata).takeUnretainedValue().update(position: position)
    return 0
}

nonisolated private final class OffsetZIPFile: @unchecked Sendable {
    let path: String
    let offset: UInt64

    init(path: String, offset: UInt64) {
        self.path = path
        self.offset = offset
    }
}

private typealias ZipOpenCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32) -> UnsafeMutableRawPointer?
private typealias ZipReadCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt) -> UInt
private typealias ZipWriteCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeRawPointer?, UInt) -> UInt
private typealias ZipTellCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UInt64
private typealias ZipSeekCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt64, Int32) -> Int
private typealias ZipCloseCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32
private typealias ZipErrorCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32

private struct ZipFileFunctions64 {
    var open: ZipOpenCallback?
    var read: ZipReadCallback?
    var write: ZipWriteCallback?
    var tell: ZipTellCallback?
    var seek: ZipSeekCallback?
    var close: ZipCloseCallback?
    var error: ZipErrorCallback?
    var opaque: UnsafeMutableRawPointer?
}

nonisolated private let offsetZipOpen: ZipOpenCallback = { opaque, _, _ in
    guard let opaque else { return nil }
    let box = Unmanaged<OffsetZIPFile>.fromOpaque(opaque).takeUnretainedValue()
    guard let file = fopen(box.path, "rb") else { return nil }
    guard fseeko(file, off_t(box.offset), SEEK_SET) == 0 else {
        fclose(file)
        return nil
    }
    return UnsafeMutableRawPointer(file)
}
nonisolated private let offsetZipRead: ZipReadCallback = { _, stream, buffer, size in
    guard let stream, let buffer else { return 0 }
    return UInt(fread(buffer, 1, Int(size), stream.assumingMemoryBound(to: FILE.self)))
}
nonisolated private let offsetZipWrite: ZipWriteCallback = { _, _, _, _ in 0 }
nonisolated private let offsetZipTell: ZipTellCallback = { opaque, stream in
    guard let opaque, let stream else { return UInt64.max }
    let box = Unmanaged<OffsetZIPFile>.fromOpaque(opaque).takeUnretainedValue()
    let position = ftello(stream.assumingMemoryBound(to: FILE.self))
    guard position >= off_t(box.offset) else { return UInt64.max }
    return UInt64(position) - box.offset
}
nonisolated private let offsetZipSeek: ZipSeekCallback = { opaque, stream, offset, origin in
    guard let opaque, let stream else { return -1 }
    let box = Unmanaged<OffsetZIPFile>.fromOpaque(opaque).takeUnretainedValue()
    let file = stream.assumingMemoryBound(to: FILE.self)
    switch origin {
    case 0: return Int(fseeko(file, off_t(box.offset + offset), SEEK_SET))
    case 1: return Int(fseeko(file, off_t(offset), SEEK_CUR))
    case 2: return Int(fseeko(file, off_t(offset), SEEK_END))
    default: return -1
    }
}
nonisolated private let offsetZipClose: ZipCloseCallback = { _, stream in
    guard let stream else { return -1 }
    return fclose(stream.assumingMemoryBound(to: FILE.self))
}
nonisolated private let offsetZipError: ZipErrorCallback = { _, stream in
    guard let stream else { return -1 }
    return ferror(stream.assumingMemoryBound(to: FILE.self))
}

struct ZIPArchiveExtractor: ArchiveExtractor {
    nonisolated let format: ArchiveFormat = .zip

    nonisolated func canHandle(_ urls: [URL]) -> Bool {
        urls.contains { url in
            let ext = url.pathExtension.lowercased()
            return ArchiveFormatDetector.detect(url) == .zip || ext.range(of: #"z\d\d"#, options: .regularExpression) != nil
        }
    }

    nonisolated func extract(_ request: ArchiveRequest) async throws -> ArchiveResult {
        try await Task.detached(priority: .userInitiated) {
            try extractSynchronously(request)
        }.value
    }

    nonisolated private func extractSynchronously(_ request: ArchiveRequest) throws -> ArchiveResult {
        let scoped = request.sourceURLs + [request.destinationURL]
        let accessed = scoped.map { $0.startAccessingSecurityScopedResource() }
        defer {
            for (url, didAccess) in zip(scoped, accessed) where didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let source = try mainZIP(in: request.sourceURLs)
        try validateSplitVolumes(around: source, selected: request.sourceURLs)
        try FileManager.default.createDirectory(at: request.destinationURL, withIntermediateDirectories: true)

        // Read the central directory first so extraction can write straight to its visible final location.
        // The modern minizip-ng reader handles SFX/prepended data, ZipCrypto, WinZip AES and split disks.
        let embeddedOffset = embeddedZIPOffset(in: source)
        let catalog = try archiveCatalog(in: source, embeddedOffset: embeddedOffset)
        let extractionDestination: URL
        if catalog.roots.count > 1 {
            extractionDestination = request.destinationURL.appendingPathComponent(
                source.deletingPathExtension().lastPathComponent,
                isDirectory: true
            )
        } else {
            extractionDestination = request.destinationURL
        }
        try FileManager.default.createDirectory(at: extractionDestination, withIntermediateDirectories: true)

        let password = request.password.flatMap { $0.isEmpty ? nil : $0 }
        let isSplitArchive = request.sourceURLs.contains {
            $0.pathExtension.lowercased().range(of: #"z\d\d"#, options: .regularExpression) != nil
        }
        let status = if isSplitArchive {
            extractSplitArchive(
                source: source,
                destination: extractionDestination,
                password: password,
                totalSize: catalog.totalSize,
                entries: catalog.entries,
                progress: request.progress
            )
        } else {
            extractEntries(
                source: source,
                destination: extractionDestination,
                password: password,
                totalSize: catalog.totalSize,
                embeddedOffset: embeddedOffset,
                progress: request.progress
            )
        }
        guard status == 0 else {
            NSLog("EasyUnpack ZIP extraction failed with minizip status %d for %@", status, source.path)
            throw mapFailure(status)
        }
        request.progress?(1)
        try removeMacOSMetadataDirectory(from: extractionDestination)
        return ArchiveResult(destinationURL: extractionDestination, format: format)
    }

    nonisolated private func removeMacOSMetadataDirectory(from staging: URL) throws {
        let metadata = staging.appendingPathComponent("__MACOSX", isDirectory: true)
        if FileManager.default.fileExists(atPath: metadata.path) {
            try FileManager.default.removeItem(at: metadata)
        }
    }

    nonisolated private struct ArchiveCatalog {
        let roots: Set<String>
        let totalSize: UInt64
        let entries: [EntryInfo]
    }

    nonisolated private func archiveCatalog(in source: URL, embeddedOffset: UInt64) throws -> ArchiveCatalog {
        guard let opened = openArchive(source, embeddedOffset: embeddedOffset) else {
            throw ArchiveError.damagedArchive
        }
        let (archive, offsetBox) = opened
        defer { _ = unzClose(archive) }
        defer { withExtendedLifetime(offsetBox) {} }

        var roots = Set<String>()
        var totalSize: UInt64 = 0
        var entries: [EntryInfo] = []
        var status = unzGoToFirstFile(archive)
        while status == 0 {
            let entry = try readEntryInfo(from: archive)
            entries.append(entry)
            totalSize &+= entry.uncompressedSize
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            if let root = path.split(separator: "/", omittingEmptySubsequences: true).first,
               root != "__MACOSX" {
                roots.insert(String(root))
            }
            status = unzGoToNextFile(archive)
        }
        guard status == -100 else { throw ArchiveError.damagedArchive }
        return ArchiveCatalog(roots: roots, totalSize: totalSize, entries: entries)
    }

    nonisolated private func mainZIP(in urls: [URL]) throws -> URL {
        guard let main = urls.first(where: { ArchiveFormatDetector.detect($0) == .zip }) else {
            throw ArchiveError.missingMainVolume
        }
        return main
    }

    nonisolated private func validateSplitVolumes(around main: URL, selected urls: [URL]) throws {
        let volumeNumbers = urls.compactMap { url -> Int? in
            let ext = url.pathExtension.lowercased()
            guard ext.hasPrefix("z"), ext.count == 3 else { return nil }
            return Int(ext.dropFirst())
        }.sorted()
        guard let last = volumeNumbers.last else { return }
        let selectedNames = Set(urls.map { $0.lastPathComponent.lowercased() })
        let base = main.deletingPathExtension().lastPathComponent
        for number in 1...last {
            let name = "\(base).z\(String(format: "%02d", number))"
            guard selectedNames.contains(name.lowercased()) else { throw ArchiveError.missingSplitVolume(name) }
        }
    }

    nonisolated private struct EntryInfo {
        let path: String
        let uncompressedSize: UInt64
        let crc32: UInt32
        let isDirectory: Bool
        let isEncrypted: Bool
    }

    nonisolated private func readEntryInfo(from archive: UnsafeMutableRawPointer) throws -> EntryInfo {
        var info = unz_file_info64()
        guard unzGetCurrentFileInfo64(archive, &info, nil, 0, nil, 0, nil, 0) == 0 else {
            throw ArchiveError.damagedArchive
        }
        var filename = [CChar](repeating: 0, count: Int(info.size_filename) + 1)
        var extra = [UInt8](repeating: 0, count: Int(info.size_file_extra))
        let status = filename.withUnsafeMutableBufferPointer { namePointer in
            extra.withUnsafeMutableBytes { extraPointer in
                unzGetCurrentFileInfo64(
                    archive, &info, namePointer.baseAddress, UInt(namePointer.count),
                    extraPointer.baseAddress, UInt(extraPointer.count), nil, 0
                )
            }
        }
        guard status == 0 else { throw ArchiveError.damagedArchive }
        let rawName = Data(filename.prefix(Int(info.size_filename)).map { UInt8(bitPattern: $0) })
        let path = unicodePath(in: Data(extra))
            ?? decodeLegacyFilename(rawName, utf8Flag: (info.flag & (1 << 11)) != 0)
        guard let path, !path.isEmpty else { throw ArchiveError.damagedArchive }
        return EntryInfo(
            path: path,
            uncompressedSize: info.uncompressed_size,
            crc32: info.crc,
            isDirectory: rawName.last == 0x2F || rawName.last == 0x5C,
            isEncrypted: (info.flag & 1) != 0
        )
    }

    nonisolated private func unicodePath(in extra: Data) -> String? {
        var offset = 0
        while offset + 4 <= extra.count {
            let id = UInt16(extra[offset]) | UInt16(extra[offset + 1]) << 8
            let length = Int(extra[offset + 2]) | Int(extra[offset + 3]) << 8
            let valueStart = offset + 4
            let valueEnd = valueStart + length
            guard valueEnd <= extra.count else { return nil }
            if id == 0x7075, length >= 5, extra[valueStart] == 1 {
                return String(data: extra[(valueStart + 5)..<valueEnd], encoding: .utf8)
            }
            offset = valueEnd
        }
        return nil
    }

    nonisolated private func decodeLegacyFilename(_ data: Data, utf8Flag: Bool) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if utf8Flag { return nil }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
        ))
        let candidates: [(text: String, language: LegacyFilenameLanguage)] = [
            String(data: data, encoding: gb18030).map { ($0, .chinese) },
            String(data: data, encoding: .shiftJIS).map { ($0, .japanese) },
            String(data: data, encoding: cp949).map { ($0, .korean) },
        ].compactMap { $0 }
        return candidates.max { legacyFilenameScore($0) < legacyFilenameScore($1) }?.text
            ?? String(data: data, encoding: .isoLatin1)
    }

    nonisolated private enum LegacyFilenameLanguage {
        case chinese, japanese, korean
    }

    nonisolated private func legacyFilenameScore(
        _ candidate: (text: String, language: LegacyFilenameLanguage)
    ) -> Int {
        var score = 0
        for scalar in candidate.text.unicodeScalars {
            let value = scalar.value
            if CharacterSet.controlCharacters.contains(scalar) { score -= 100 }
            if (0x3400...0x9FFF).contains(value) { score += 2 }
            switch candidate.language {
            case .chinese:
                break
            case .japanese:
                if (0x3040...0x30FF).contains(value) || (0x31F0...0x31FF).contains(value) {
                    score += 12
                }
            case .korean:
                if (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value) ||
                    (0xAC00...0xD7AF).contains(value) {
                    score += 12
                }
            }
        }
        return score
    }

    nonisolated private func safeOutputURL(for path: String, under destination: URL) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { return nil }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              !components.contains(where: { $0 == "." || $0 == ".." }),
              components.first != "__MACOSX" else { return nil }
        return components.reduce(destination) { $0.appendingPathComponent(String($1)) }
    }

    nonisolated private func extractEntries(
        source: URL,
        destination: URL,
        password: String?,
        totalSize: UInt64,
        embeddedOffset: UInt64,
        progress: (@Sendable (Double) -> Void)?
    ) -> Int32 {
        guard let opened = openArchive(source, embeddedOffset: embeddedOffset) else { return -104 }
        let (archive, offsetBox) = opened
        defer { _ = unzClose(archive) }
        defer { withExtendedLifetime(offsetBox) {} }

        var completed: UInt64 = 0
        let passwordCandidates = password.map(passwordDataCandidates) ?? []
        var selectedPassword: Data?
        var status = unzGoToFirstFile(archive)
        while status == 0 {
            let entry: EntryInfo
            do { entry = try readEntryInfo(from: archive) } catch { return -103 }
            guard let output = safeOutputURL(for: entry.path, under: destination) else {
                status = unzGoToNextFile(archive)
                continue
            }
            do {
                if entry.isDirectory {
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(
                        at: output.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    _ = FileManager.default.createFile(atPath: output.path, contents: nil)
                    let file = try FileHandle(forWritingTo: output)
                    defer { try? file.close() }

                    let openStatus: Int32
                    if !entry.isEncrypted {
                        openStatus = unzOpenCurrentFilePassword(archive, nil)
                    } else if let selectedPassword {
                        openStatus = openCurrentFile(archive, password: selectedPassword)
                    } else {
                        var candidateStatus: Int32 = -108
                        for candidate in passwordCandidates {
                            candidateStatus = openCurrentFile(archive, password: candidate)
                            if candidateStatus == 0 {
                                selectedPassword = candidate
                                break
                            }
                        }
                        openStatus = candidateStatus
                    }
                    guard openStatus == 0 else { return openStatus }
                    var buffer = [UInt8](repeating: 0, count: 256 * 1024)
                    while true {
                        let count = buffer.withUnsafeMutableBytes {
                            unzReadCurrentFile(archive, $0.baseAddress, UInt32($0.count))
                        }
                        if count < 0 {
                            _ = unzCloseCurrentFile(archive)
                            return count
                        }
                        if count == 0 { break }
                        try file.write(contentsOf: Data(buffer.prefix(Int(count))))
                        completed &+= UInt64(count)
                        progress?(min(Double(completed) / Double(max(totalSize, 1)), 0.99))
                    }
                    let closeStatus = unzCloseCurrentFile(archive)
                    guard closeStatus == 0 else { return closeStatus }
                }
            } catch {
                return -116
            }
            status = unzGoToNextFile(archive)
        }
        return status == -100 ? 0 : status
    }

    nonisolated private func extractSplitArchive(
        source: URL,
        destination: URL,
        password: String?,
        totalSize: UInt64,
        entries: [EntryInfo],
        progress: (@Sendable (Double) -> Void)?
    ) -> Int32 {
        var reader: UnsafeMutableRawPointer?
        guard mzZipReaderCreate(&reader) != nil, let reader else { return -104 }
        defer {
            _ = mzZipReaderClose(reader)
            var handle: UnsafeMutableRawPointer? = reader
            mzZipReaderDelete(&handle)
        }

        let openStatus = source.path.withCString { mzZipReaderOpenFile(reader, $0) }
        guard openStatus == 0 else { return openStatus }
        mzZipReaderSetEncoding(reader, 936)

        var progressBox: MinizipProgressBox?
        if let progress, totalSize > 0 {
            let box = MinizipProgressBox(
                total: Int64(min(totalSize, UInt64(Int64.max))), report: progress
            )
            progressBox = box
            mzZipReaderSetProgressInterval(reader, 100)
            mzZipReaderSetProgressCallback(
                reader,
                Unmanaged.passUnretained(box).toOpaque(),
                minizipProgressCallback
            )
        }
        defer { withExtendedLifetime(progressBox) {} }

        let saveEntries: () -> Int32 = {
            guard !entries.isEmpty else { return 0 }
            var status = mzZipReaderGotoFirstEntry(reader)
            for (index, entry) in entries.enumerated() {
                guard status == 0 else { return status }
                if let output = safeOutputURL(for: entry.path, under: destination) {
                    do {
                        if entry.isDirectory {
                            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        } else {
                            try FileManager.default.createDirectory(
                                at: output.deletingLastPathComponent(), withIntermediateDirectories: true
                            )
                            status = output.path.withCString { mzZipReaderEntrySaveFile(reader, $0) }
                            if status == -3, outputMatchesCatalog(output, entry: entry) {
                                status = 0
                            }
                            guard status == 0 else {
                                NSLog(
                                    "EasyUnpack split ZIP entry failed with status %d at index %d: %@",
                                    status, index, entry.path
                                )
                                return status
                            }
                        }
                    } catch {
                        return -116
                    }
                }
                // The catalog already gives us the exact entry count. Do not ask minizip
                // to advance beyond the final entry: some valid split archives report a
                // zlib data error there even though the final entry was saved successfully.
                if index + 1 < entries.count {
                    status = mzZipReaderGotoNextEntry(reader)
                }
            }
            return 0
        }
        guard let password else { return saveEntries() }
        return password.withCString { pointer in
            mzZipReaderSetPassword(reader, pointer)
            return saveEntries()
        }
    }

    nonisolated private func outputMatchesCatalog(_ output: URL, entry: EntryInfo) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: output.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value == entry.uncompressedSize,
              let file = try? FileHandle(forReadingFrom: output) else { return false }
        defer { try? file.close() }

        var checksum = zlibCRC32(0, nil, 0)
        do {
            while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
                checksum = data.withUnsafeBytes { bytes in
                    zlibCRC32(
                        checksum,
                        bytes.bindMemory(to: UInt8.self).baseAddress,
                        UInt32(bytes.count)
                    )
                }
            }
            return UInt32(truncatingIfNeeded: checksum) == entry.crc32
        } catch {
            return false
        }
    }

    nonisolated private func openCurrentFile(
        _ archive: UnsafeMutableRawPointer, password: Data
    ) -> Int32 {
        var nulTerminated = password
        nulTerminated.append(0)
        return nulTerminated.withUnsafeBytes { bytes in
            unzOpenCurrentFilePassword(
                archive,
                bytes.bindMemory(to: CChar.self).baseAddress
            )
        }
    }

    nonisolated private func passwordDataCandidates(_ password: String) -> [Data] {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
        ))
        let encodings: [String.Encoding] = [.utf8, gb18030, .shiftJIS, cp949]
        var seen = Set<Data>()
        return encodings.compactMap { password.data(using: $0, allowLossyConversion: false) }
            .filter { seen.insert($0).inserted }
    }

    nonisolated private func openArchive(
        _ source: URL, embeddedOffset: UInt64
    ) -> (UnsafeMutableRawPointer, OffsetZIPFile?)? {
        guard embeddedOffset > 0 else {
            return source.path.withCString { path in
                unzOpen64(UnsafeRawPointer(path)).map { ($0, nil) }
            }
        }
        let box = OffsetZIPFile(path: source.path, offset: embeddedOffset)
        var functions = ZipFileFunctions64(
            open: offsetZipOpen,
            read: offsetZipRead,
            write: offsetZipWrite,
            tell: offsetZipTell,
            seek: offsetZipSeek,
            close: offsetZipClose,
            error: offsetZipError,
            opaque: Unmanaged.passUnretained(box).toOpaque()
        )
        let archive = withUnsafeMutablePointer(to: &functions) {
            unzOpen2_64(nil, UnsafeMutableRawPointer($0))
        }
        return archive.map { ($0, box) }
    }

    nonisolated private func embeddedZIPOffset(in source: URL) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: source) else { return 0 }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return 0 }
        let tailSize = min(size, 131_072)
        try? handle.seek(toOffset: size - tailSize)
        guard let tail = try? handle.read(upToCount: Int(tailSize)),
              let eocd = tail.range(of: Data([0x50, 0x4B, 0x05, 0x06]), options: .backwards),
              eocd.lowerBound + 20 <= tail.count else { return 0 }

        func uint32(_ offset: Int) -> UInt64 {
            UInt64(tail[offset]) |
                UInt64(tail[offset + 1]) << 8 |
                UInt64(tail[offset + 2]) << 16 |
                UInt64(tail[offset + 3]) << 24
        }
        if eocd.lowerBound >= 20 {
            let locatorStart = eocd.lowerBound - 20
            let locatorSignature = Data([0x50, 0x4B, 0x06, 0x07])
            if tail[locatorStart..<(locatorStart + 4)] == locatorSignature,
               let zip64Range = tail[..<locatorStart].range(
                   of: Data([0x50, 0x4B, 0x06, 0x06]), options: .backwards
               ) {
                let physicalZip64 = size - tailSize + UInt64(zip64Range.lowerBound)
                func uint64(_ offset: Int) -> UInt64 {
                    (0..<8).reduce(0) { result, byte in
                        result | UInt64(tail[offset + byte]) << UInt64(byte * 8)
                    }
                }
                let logicalZip64 = uint64(locatorStart + 8)
                if physicalZip64 >= logicalZip64 { return physicalZip64 - logicalZip64 }
            }
        }
        let centralSize = uint32(eocd.lowerBound + 12)
        let centralOffset = uint32(eocd.lowerBound + 16)
        guard centralSize != 0xFFFF_FFFF, centralOffset != 0xFFFF_FFFF else { return 0 }
        let physicalEOCD = size - tailSize + UInt64(eocd.lowerBound)
        let logicalEOCD = centralOffset + centralSize
        return physicalEOCD >= logicalEOCD ? physicalEOCD - logicalEOCD : 0
    }

    nonisolated private func mapFailure(_ status: Int32) -> ArchiveError {
        switch status {
        case -108: return .invalidPassword
        case -103, -105, -106: return .damagedArchive
        default: return .extractionFailed("ZIP 解压失败（minizip 错误码 \(status)）。")
        }
    }
}
