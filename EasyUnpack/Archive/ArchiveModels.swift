import Foundation

enum ArchiveFormat: String, CaseIterable, Sendable {
    case zip
    case tar
    case sevenZ = "7z"

    var displayName: String { rawValue.uppercased() }
}

struct ArchiveRequest: Sendable {
    let sourceURLs: [URL]
    let destinationURL: URL
    let password: String?
    let progress: (@Sendable (Double) -> Void)?
}

struct ArchiveResult: Sendable {
    let destinationURL: URL
    let format: ArchiveFormat
}

enum ArchiveError: LocalizedError, Sendable {
    case noSource
    case unsupportedFormat(String)
    case missingMainVolume
    case missingSplitVolume(String)
    case invalidPassword
    case damagedArchive
    case trashFailed(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSource: return "请选择压缩文件。"
        case .unsupportedFormat(let ext): return "暂不支持 \(ext.isEmpty ? "该" : ext.uppercased()) 格式。"
        case .missingMainVolume: return "分卷中缺少主 .zip 文件。"
        case .missingSplitVolume(let name): return "分卷不完整，缺少 \(name)。"
        case .invalidPassword: return "密码错误，无法解密该 ZIP。"
        case .damagedArchive: return "压缩文件已损坏、格式不正确或分卷不完整。"
        case .trashFailed(let message): return "文件已解压，但原压缩文件无法移到废纸篓：\(message)"
        case .extractionFailed(let message): return message
        }
    }
}

protocol ArchiveExtractor: Sendable {
    nonisolated var format: ArchiveFormat { get }
    nonisolated func canHandle(_ urls: [URL]) -> Bool
    nonisolated func extract(_ request: ArchiveRequest) async throws -> ArchiveResult
}
