import Foundation

enum ArchiveFormat: String, CaseIterable, Sendable {
    case zip
    case tar
    case sevenZ = "7z"
    case rar

    var displayName: String { rawValue.uppercased() }
}

enum ArchiveFormatDetector {
    nonisolated static func detect(_ url: URL) -> ArchiveFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let prefix = (try? handle.read(upToCount: 512)) ?? Data()
        if prefix.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZ }
        if prefix.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) { return .rar }
        if prefix.starts(with: [0x50, 0x4B, 0x03, 0x04]) ||
            prefix.starts(with: [0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if prefix.count >= 262,
           prefix.subdata(in: 257..<262) == Data("ustar".utf8) { return .tar }

        guard let size = try? handle.seekToEnd() else { return nil }
        let tailSize = min(size, 131_072)
        try? handle.seek(toOffset: size - tailSize)
        let tail = (try? handle.read(upToCount: Int(tailSize))) ?? Data()
        let zipSignatures = [
            Data([0x50, 0x4B, 0x05, 0x06]), // end of central directory
            Data([0x50, 0x4B, 0x06, 0x06]), // ZIP64 end of central directory
        ]
        if zipSignatures.contains(where: { tail.range(of: $0, options: .backwards) != nil }) {
            return .zip
        }
        return nil
    }
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
