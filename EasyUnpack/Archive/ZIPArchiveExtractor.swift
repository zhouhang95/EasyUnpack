import Foundation
import ZipArchive

@_silgen_name("mz_zip_reader_create")
nonisolated private func mzZipReaderCreate(_ handle: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> UnsafeMutableRawPointer?
@_silgen_name("mz_zip_reader_delete")
nonisolated private func mzZipReaderDelete(_ handle: UnsafeMutablePointer<UnsafeMutableRawPointer?>)
@_silgen_name("mz_zip_reader_open_file")
nonisolated private func mzZipReaderOpenFile(_ handle: UnsafeMutableRawPointer?, _ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("mz_zip_reader_set_password")
nonisolated private func mzZipReaderSetPassword(_ handle: UnsafeMutableRawPointer?, _ password: UnsafePointer<CChar>)
@_silgen_name("mz_zip_reader_save_all")
nonisolated private func mzZipReaderSaveAll(_ handle: UnsafeMutableRawPointer?, _ destination: UnsafePointer<CChar>) -> Int32
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

struct ZIPArchiveExtractor: ArchiveExtractor {
    nonisolated let format: ArchiveFormat = .zip

    nonisolated func canHandle(_ urls: [URL]) -> Bool {
        urls.contains { url in
            let ext = url.pathExtension.lowercased()
            return ext == "zip" || ext.range(of: #"z\d\d"#, options: .regularExpression) != nil
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
        let rootItems = try archiveRootItems(in: source)
        let extractionDestination: URL
        if rootItems.count > 1 {
            extractionDestination = request.destinationURL.appendingPathComponent(
                source.deletingPathExtension().lastPathComponent,
                isDirectory: true
            )
        } else {
            extractionDestination = request.destinationURL
        }
        try FileManager.default.createDirectory(at: extractionDestination, withIntermediateDirectories: true)

        var sizeError: NSError?
        let totalSize = SSZipArchive.payloadSizeForArchive(atPath: source.path, error: &sizeError).int64Value
        let status = extractWithMinizip(
            source: source,
            destination: extractionDestination,
            password: request.password.flatMap { $0.isEmpty ? nil : $0 },
            totalSize: totalSize,
            progress: request.progress
        )
        guard status == 0 else { throw mapFailure(status) }
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

    nonisolated private func archiveRootItems(in source: URL) throws -> Set<String> {
        let archive = source.path.withCString { unzOpen64(UnsafeRawPointer($0)) }
        guard let archive else { throw ArchiveError.damagedArchive }
        defer { _ = unzClose(archive) }

        var roots = Set<String>()
        var status = unzGoToFirstFile(archive)
        while status == 0 {
            var buffer = [CChar](repeating: 0, count: 65_536)
            let infoStatus = buffer.withUnsafeMutableBufferPointer { pointer in
                unzGetCurrentFileInfo64(
                    archive, nil, pointer.baseAddress, UInt(pointer.count),
                    nil, 0, nil, 0
                )
            }
            guard infoStatus == 0 else { throw ArchiveError.damagedArchive }
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let path = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\\", with: "/")
            if let root = path.split(separator: "/", omittingEmptySubsequences: true).first,
               root != "__MACOSX" {
                roots.insert(String(root))
            }
            status = unzGoToNextFile(archive)
        }
        return roots
    }

    nonisolated private func mainZIP(in urls: [URL]) throws -> URL {
        guard let main = urls.first(where: { $0.pathExtension.lowercased() == "zip" }) else {
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

    nonisolated private func extractWithMinizip(
        source: URL,
        destination: URL,
        password: String?,
        totalSize: Int64,
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

        var progressBox: MinizipProgressBox?
        if let progress, totalSize > 0 {
            let box = MinizipProgressBox(total: totalSize, report: progress)
            progressBox = box
            mzZipReaderSetProgressInterval(reader, 100)
            mzZipReaderSetProgressCallback(
                reader,
                Unmanaged.passUnretained(box).toOpaque(),
                minizipProgressCallback
            )
        }
        defer { withExtendedLifetime(progressBox) {} }

        let save: () -> Int32 = {
            destination.path.withCString { mzZipReaderSaveAll(reader, $0) }
        }
        guard let password else { return save() }
        return password.withCString { pointer in
            mzZipReaderSetPassword(reader, pointer)
            return save()
        }
    }

    nonisolated private func mapFailure(_ status: Int32) -> ArchiveError {
        switch status {
        case -108: return .invalidPassword
        case -103, -105, -106: return .damagedArchive
        default: return .extractionFailed("ZIP 解压失败（minizip 错误码 \(status)）。")
        }
    }
}
