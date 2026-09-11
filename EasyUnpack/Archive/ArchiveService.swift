import Foundation

final class ArchiveService: Sendable {
    private let extractors: [any ArchiveExtractor]
    private let maximumNestedDepth = 32

    init(extractors: [any ArchiveExtractor] = [ZIPArchiveExtractor(), TARArchiveExtractor(), SevenZipArchiveExtractor(), RARArchiveExtractor()]) {
        self.extractors = extractors
    }

    nonisolated func extract(_ request: ArchiveRequest) async throws -> ArchiveResult {
        guard !request.sourceURLs.isEmpty else { throw ArchiveError.noSource }

        var currentRequest = request
        var activeNestedArchiveURLs: [URL] = []

        for depth in 0..<maximumNestedDepth {
            guard let extractor = extractors.first(where: { $0.canHandle(currentRequest.sourceURLs) }) else {
                throw ArchiveError.unsupportedFormat(currentRequest.sourceURLs[0].pathExtension)
            }

            let layerWeight = pow(0.5, Double(depth + 1))
            let layerStart = 1 - pow(0.5, Double(depth))
            let layerRequest = ArchiveRequest(
                sourceURLs: currentRequest.sourceURLs,
                destinationURL: currentRequest.destinationURL,
                password: currentRequest.password,
                progress: request.progress.map { report in
                    { value in
                        report(min(layerStart + max(0, value) * layerWeight, 0.99))
                    }
                }
            )
            let result = try await extractor.extract(layerRequest)

            guard let nestedArchive = nextNestedArchive(in: result.topLevelURLs) else {
                request.progress?(1)
                return ArchiveResult(
                    destinationURL: result.destinationURL,
                    format: result.format,
                    topLevelURLs: result.topLevelURLs,
                    nestedArchiveURLs: activeNestedArchiveURLs
                )
            }

            try trashCompletedSources(currentRequest.sourceURLs)
            let renamedArchive = try renameArchiveToMatchDetectedFormat(nestedArchive)
            activeNestedArchiveURLs = [renamedArchive]
            currentRequest = ArchiveRequest(
                sourceURLs: [renamedArchive],
                destinationURL: renamedArchive.deletingLastPathComponent(),
                password: request.password,
                progress: nil
            )
        }

        throw ArchiveError.extractionFailed("内层压缩文件超过 \(maximumNestedDepth) 层，已停止自动解压。")
    }

    nonisolated private func nextNestedArchive(in topLevelURLs: [URL]) -> URL? {
        guard topLevelURLs.count == 1 else { return nil }
        let candidate = topLevelURLs[0]
        guard (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              ArchiveFormatDetector.detect(candidate) != nil else { return nil }
        return candidate
    }

    nonisolated private func trashCompletedSources(_ urls: [URL]) throws {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                throw ArchiveError.trashFailed(error.localizedDescription)
            }
        }
    }

    nonisolated private func renameArchiveToMatchDetectedFormat(_ archive: URL) throws -> URL {
        guard let format = ArchiveFormatDetector.detect(archive) else {
            throw ArchiveError.damagedArchive
        }
        let expectedExtension = format.rawValue
        if archive.pathExtension.lowercased() == expectedExtension {
            return archive
        }

        let base = archive.pathExtension.isEmpty ? archive : archive.deletingPathExtension()
        let renamed = base.appendingPathExtension(expectedExtension)
        guard !FileManager.default.fileExists(atPath: renamed.path) else {
            throw ArchiveError.extractionFailed(
                "无法重命名内层压缩文件，目标已存在：\(renamed.lastPathComponent)"
            )
        }
        do {
            try FileManager.default.moveItem(at: archive, to: renamed)
            return renamed
        } catch {
            throw ArchiveError.extractionFailed(
                "无法为内层压缩文件添加 .\(expectedExtension) 扩展名：\(error.localizedDescription)"
            )
        }
    }
}
