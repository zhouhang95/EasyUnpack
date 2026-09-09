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
        var nestedArchiveURLs: [URL] = []
        var visitedPaths = Set(request.sourceURLs.map { $0.standardizedFileURL.path })

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
                    nestedArchiveURLs: nestedArchiveURLs
                )
            }

            let path = nestedArchive.standardizedFileURL.path
            guard visitedPaths.insert(path).inserted else {
                throw ArchiveError.extractionFailed("检测到重复的内层压缩文件，已停止自动解压：\(nestedArchive.lastPathComponent)")
            }
            nestedArchiveURLs.append(nestedArchive)
            currentRequest = ArchiveRequest(
                sourceURLs: [nestedArchive],
                destinationURL: nestedArchive.deletingLastPathComponent(),
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
}
