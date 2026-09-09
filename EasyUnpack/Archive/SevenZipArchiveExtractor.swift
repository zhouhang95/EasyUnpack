import Foundation
import PLzmaSDK

nonisolated private final class SevenZipProgressRelay: DecoderDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func decoder(decoder: Decoder, path: String, progress: Double) {
        report(min(max(progress, 0), 0.99))
    }
}

struct SevenZipArchiveExtractor: ArchiveExtractor {
    nonisolated let format: ArchiveFormat = .sevenZ

    nonisolated func canHandle(_ urls: [URL]) -> Bool {
        urls.contains { url in
            let ext = url.pathExtension.lowercased()
            return ArchiveFormatDetector.detect(url) == .sevenZ || ext == "001"
        }
    }

    nonisolated func extract(_ request: ArchiveRequest) async throws -> ArchiveResult {
        try await Task.detached(priority: .userInitiated) {
            try extractSynchronously(request)
        }.value
    }

    nonisolated private func extractSynchronously(_ request: ArchiveRequest) throws -> ArchiveResult {
        guard let source = request.sourceURLs.first(where: { ArchiveFormatDetector.detect($0) == .sevenZ })
            ?? request.sourceURLs.first(where: { $0.pathExtension.lowercased() == "001" }) else {
            throw ArchiveError.noSource
        }
        let scoped = request.sourceURLs + [request.destinationURL]
        let accessed = scoped.map { $0.startAccessingSecurityScopedResource() }
        defer {
            for (url, didAccess) in zip(scoped, accessed) where didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let relay = request.progress.map(SevenZipProgressRelay.init(report:))
            let stream = try inputStream(for: source, volumes: request.sourceURLs)
            let decoder = try Decoder(stream: stream, fileType: .sevenZ, delegate: relay)
            try decoder.setPassword(request.password)
            guard try decoder.open() else { throw ArchiveError.damagedArchive }

            let allItems = try decoder.items()
            var selected: [Item] = []
            var roots = Set<String>()
            for index in 0..<allItems.count {
                let item = try allItems.item(at: index)
                let itemPath = try item.path().description
                guard let components = safeComponents(itemPath) else {
                    throw ArchiveError.extractionFailed("7z 包含不安全的文件路径：\(itemPath)")
                }
                guard components.first != "__MACOSX" else { continue }
                roots.insert(components[0])
                selected.append(item)
            }

            let destination = roots.count > 1
                ? request.destinationURL.appendingPathComponent(archiveBaseName(source), isDirectory: true)
                : request.destinationURL
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

            if !selected.isEmpty {
                let items = try ItemArray(items: selected)
                let succeeded = try decoder.extract(
                    items: items,
                    to: PLzmaSDK.Path(destination.path),
                    itemsFullPath: true
                )
                guard succeeded else { throw ArchiveError.damagedArchive }
            }
            request.progress?(1)
            return ArchiveResult(
                destinationURL: destination,
                format: format,
                topLevelURLs: roots.map { destination.appendingPathComponent($0) }
            )
        } catch let error as ArchiveError {
            NSLog("EasyUnpack 7z extraction failed for %@: %@", source.path, error.localizedDescription)
            throw error
        } catch {
            NSLog("EasyUnpack 7z extraction failed for %@: %@", source.path, String(describing: error))
            throw map(error, passwordWasProvided: request.password?.isEmpty == false)
        }
    }

    nonisolated private func inputStream(for source: URL, volumes: [URL]) throws -> InStream {
        guard source.pathExtension == "001" else {
            return try InStream(path: PLzmaSDK.Path(source.path))
        }

        let base = source.deletingPathExtension().path.lowercased()
        let ordered = volumes.filter { volume in
            volume.deletingPathExtension().path.lowercased() == base &&
                volume.pathExtension.count == 3 &&
                volume.pathExtension.allSatisfy(\.isNumber)
        }.sorted { $0.pathExtension < $1.pathExtension }
        guard !ordered.isEmpty else { throw ArchiveError.missingMainVolume }
        for (offset, volume) in ordered.enumerated() {
            let expected = String(format: "%03d", offset + 1)
            guard volume.pathExtension == expected else {
                throw ArchiveError.missingSplitVolume(source.deletingPathExtension().lastPathComponent + "." + expected)
            }
        }
        let streams = try ordered.map { try InStream(path: PLzmaSDK.Path($0.path)) }
        return try InStream(streams: streams)
    }

    nonisolated private func archiveBaseName(_ source: URL) -> String {
        let withoutLastExtension = source.deletingPathExtension()
        if source.pathExtension == "001", withoutLastExtension.pathExtension.lowercased() == "7z" {
            return withoutLastExtension.deletingPathExtension().lastPathComponent
        }
        return withoutLastExtension.lastPathComponent
    }

    nonisolated private func safeComponents(_ path: String) -> [String]? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { return nil }
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        return parts
    }

    nonisolated private func map(_ error: Error, passwordWasProvided: Bool) -> ArchiveError {
        let text = String(describing: error)
        let lower = text.lowercased()
        if lower.contains("password") || lower.contains("crypto") || passwordWasProvided {
            return .invalidPassword
        }
        return .extractionFailed("7z 解压失败：\(text)")
    }
}
