import Foundation

final class ArchiveService: Sendable {
    private let extractors: [any ArchiveExtractor]

    init(extractors: [any ArchiveExtractor] = [ZIPArchiveExtractor(), TARArchiveExtractor(), SevenZipArchiveExtractor(), RARArchiveExtractor()]) {
        self.extractors = extractors
    }

    nonisolated func extract(_ request: ArchiveRequest) async throws -> ArchiveResult {
        guard !request.sourceURLs.isEmpty else { throw ArchiveError.noSource }
        guard let extractor = extractors.first(where: { $0.canHandle(request.sourceURLs) }) else {
            throw ArchiveError.unsupportedFormat(request.sourceURLs[0].pathExtension)
        }
        return try await extractor.extract(request)
    }
}
