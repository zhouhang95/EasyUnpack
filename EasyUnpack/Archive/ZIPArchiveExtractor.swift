import Foundation
import ZipArchive

@_silgen_name("mz_zip_reader_create")
private func mzZipReaderCreate(_ handle: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> UnsafeMutableRawPointer?
@_silgen_name("mz_zip_reader_delete")
private func mzZipReaderDelete(_ handle: UnsafeMutablePointer<UnsafeMutableRawPointer?>)
@_silgen_name("mz_zip_reader_open_file")
private func mzZipReaderOpenFile(_ handle: UnsafeMutableRawPointer?, _ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("mz_zip_reader_set_password")
private func mzZipReaderSetPassword(_ handle: UnsafeMutableRawPointer?, _ password: UnsafePointer<CChar>)
@_silgen_name("mz_zip_reader_save_all")
private func mzZipReaderSaveAll(_ handle: UnsafeMutableRawPointer?, _ destination: UnsafePointer<CChar>) -> Int32
@_silgen_name("mz_zip_reader_close")
private func mzZipReaderClose(_ handle: UnsafeMutableRawPointer?) -> Int32

struct ZIPArchiveExtractor: ArchiveExtractor {
    let format: ArchiveFormat = .zip

    func canHandle(_ urls: [URL]) -> Bool {
        urls.contains { url in
            let ext = url.pathExtension.lowercased()
            return ext == "zip" || ext.range(of: #"z\d\d"#, options: .regularExpression) != nil
        }
    }

    func extract(_ request: ArchiveRequest) async throws -> ArchiveResult {
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

        // Extract inside the source directory, then apply EasyUnpack's root-item policy.
        // The modern minizip-ng reader handles SFX/prepended data, ZipCrypto, WinZip AES and split disks.
        let staging = request.destinationURL
            .appendingPathComponent(".EasyUnpack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }

        let status = extractWithMinizip(
            source: source,
            destination: staging,
            password: request.password.flatMap { $0.isEmpty ? nil : $0 }
        )
        guard status == 0 else { throw mapFailure(status) }
        try removeMacOSMetadataDirectory(from: staging)

        let actualDestination = try placeExtractedItems(
            from: staging,
            beside: source,
            parent: request.destinationURL
        )
        return ArchiveResult(destinationURL: actualDestination, format: format)
    }

    private func removeMacOSMetadataDirectory(from staging: URL) throws {
        let metadata = staging.appendingPathComponent("__MACOSX", isDirectory: true)
        if FileManager.default.fileExists(atPath: metadata.path) {
            try FileManager.default.removeItem(at: metadata)
        }
    }

    private func placeExtractedItems(from staging: URL, beside source: URL, parent: URL) throws -> URL {
        let manager = FileManager.default
        let allItems = try manager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: nil,
            options: []
        )
        let meaningfulItems = allItems.filter { $0.lastPathComponent != "__MACOSX" }

        if meaningfulItems.count > 1 {
            let container = parent.appendingPathComponent(
                source.deletingPathExtension().lastPathComponent,
                isDirectory: true
            )
            try manager.createDirectory(at: container, withIntermediateDirectories: true)
            for item in meaningfulItems {
                try merge(item, into: container.appendingPathComponent(item.lastPathComponent))
            }
            return container
        }

        for item in meaningfulItems {
            try merge(item, into: parent.appendingPathComponent(item.lastPathComponent))
        }
        return parent
    }

    private func merge(_ source: URL, into destination: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        let sourceExists = manager.fileExists(atPath: source.path, isDirectory: &isDirectory)
        guard sourceExists else { return }

        var destinationIsDirectory: ObjCBool = false
        let destinationExists = manager.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory)
        if isDirectory.boolValue, destinationExists, destinationIsDirectory.boolValue {
            let children = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for child in children {
                try merge(child, into: destination.appendingPathComponent(child.lastPathComponent))
            }
            try manager.removeItem(at: source)
            return
        }

        if destinationExists { try manager.removeItem(at: destination) }
        try manager.moveItem(at: source, to: destination)
    }

    private func mainZIP(in urls: [URL]) throws -> URL {
        guard let main = urls.first(where: { $0.pathExtension.lowercased() == "zip" }) else {
            throw ArchiveError.missingMainVolume
        }
        return main
    }

    private func validateSplitVolumes(around main: URL, selected urls: [URL]) throws {
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

    private func extractWithMinizip(source: URL, destination: URL, password: String?) -> Int32 {
        var reader: UnsafeMutableRawPointer?
        guard mzZipReaderCreate(&reader) != nil, let reader else { return -104 }
        defer {
            _ = mzZipReaderClose(reader)
            var handle: UnsafeMutableRawPointer? = reader
            mzZipReaderDelete(&handle)
        }

        let openStatus = source.path.withCString { mzZipReaderOpenFile(reader, $0) }
        guard openStatus == 0 else { return openStatus }

        let save: () -> Int32 = {
            destination.path.withCString { mzZipReaderSaveAll(reader, $0) }
        }
        guard let password else { return save() }
        return password.withCString { pointer in
            mzZipReaderSetPassword(reader, pointer)
            return save()
        }
    }

    private func mapFailure(_ status: Int32) -> ArchiveError {
        switch status {
        case -108: return .invalidPassword
        case -103, -105, -106: return .damagedArchive
        default: return .extractionFailed("ZIP 解压失败（minizip 错误码 \(status)）。")
        }
    }
}
