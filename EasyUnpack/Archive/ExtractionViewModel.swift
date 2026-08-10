import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ExtractionViewModel {
    var sourceURLs: [URL] = []
    var destinationURL: URL?
    var password = ""
    var isExtracting = false
    var extractionProgress = 0.0
    var message: String?
    var isError = false

    private let service = ArchiveService()
    @ObservationIgnored private var didReadPasteboard = false

    var sourceSummary: String {
        guard !sourceURLs.isEmpty else { return "尚未选择" }
        if sourceURLs.count == 1 { return sourceURLs[0].lastPathComponent }
        return "\(sourceURLs.first(where: { $0.pathExtension.lowercased() == "zip" })?.lastPathComponent ?? sourceURLs[0].lastPathComponent) 等 \(sourceURLs.count) 个分卷"
    }

    var archiveDirectory: URL? {
        let mainArchive = sourceURLs.first(where: { $0.pathExtension.lowercased() == "zip" }) ?? sourceURLs.first
        return mainArchive?.deletingLastPathComponent()
    }

    func loadPasswordFromPasteboardIfNeeded() {
        guard !didReadPasteboard, password.isEmpty else { return }
        didReadPasteboard = true

        let pasteboard = NSPasteboard.general
        guard pasteboard.types?.contains(.string) == true,
              pasteboard.types?.contains(.fileURL) != true,
              let text = pasteboard.string(forType: .string) else { return }
        password = text
    }

    /// Receives archives opened from Finder's “Open With” menu.
    func acceptOpenedFiles(_ urls: [URL]) {
        var archiveURLs = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "zip" || ext == "tar" || ext == "7z" || ext == "001" || ext.range(of: #"z\d\d"#, options: .regularExpression) != nil
        }
        guard !archiveURLs.isEmpty else {
            isError = true
            message = "Finder 传入的文件不是受支持的 ZIP、TAR 或 7z 文件。"
            return
        }

        if let main = archiveURLs.first(where: { $0.pathExtension.lowercased() == "zip" }) {
            archiveURLs = Array(Set(archiveURLs + relatedVolumes(for: main)))
        } else if let firstVolume = archiveURLs.first(where: { $0.pathExtension == "001" }) {
            archiveURLs = Array(Set(archiveURLs + relatedSevenZipVolumes(for: firstVolume)))
        }

        let openedBase = archiveURLs[0].deletingPathExtension().path
        let matchingExisting = sourceURLs.filter { $0.deletingPathExtension().path == openedBase }
        let combined = Dictionary(uniqueKeysWithValues: (matchingExisting + archiveURLs).map { ($0.path, $0) })
        sourceURLs = Array(combined.values).sorted { lhs, rhs in
            if lhs.pathExtension.lowercased() == "zip" { return false }
            if rhs.pathExtension.lowercased() == "zip" { return true }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
        destinationURL = archiveDirectory
        isError = false
        message = "已从 Finder 接收文件，将解压到压缩包所在目录。"

        // Split ZIP volumes are discovered from the archive's directory, so extraction can start immediately.
        if sourceURLs.contains(where: {
            let ext = $0.pathExtension.lowercased()
            return ext == "zip" || ext == "tar" || ext == "7z" || ext == "001"
        }) {
            extract()
        }
    }

    func chooseSources() {
        let panel = NSOpenPanel()
        panel.title = "选择 ZIP 或全部分卷"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .zip,
            UTType(filenameExtension: "tar") ?? .data,
            UTType(filenameExtension: "7z") ?? .data,
            .data
        ]
        guard panel.runModal() == .OK else { return }
        sourceURLs = panel.urls
        if let main = sourceURLs.first(where: { $0.pathExtension.lowercased() == "zip" }) {
            sourceURLs = Array(Set(sourceURLs + relatedVolumes(for: main)))
        } else if let firstVolume = sourceURLs.first(where: { $0.pathExtension == "001" }) {
            sourceURLs = Array(Set(sourceURLs + relatedSevenZipVolumes(for: firstVolume)))
        }
        destinationURL = archiveDirectory
        message = nil
    }

    func extract() {
        guard let destinationURL = archiveDirectory else {
            isError = true
            message = "无法确定压缩包所在目录。"
            return
        }
        self.destinationURL = destinationURL
        isExtracting = true
        extractionProgress = 0
        message = nil
        let request = ArchiveRequest(
            sourceURLs: sourceURLs,
            destinationURL: destinationURL,
            password: password.isEmpty ? nil : password,
            progress: { [self] value in
                Task { @MainActor in extractionProgress = value }
            }
        )
        Task {
            do {
                let result = try await service.extract(request)
                try await moveOriginalsToTrash(request.sourceURLs)
                isError = false
                message = "解压完成：\(result.destinationURL.path)"
                NSApp.terminate(nil)
            } catch {
                isError = true
                message = error.localizedDescription
            }
            isExtracting = false
            extractionProgress = 0
        }
    }

    private func relatedVolumes(for mainZIP: URL) -> [URL] {
        let directory = mainZIP.deletingLastPathComponent()
        let base = mainZIP.deletingPathExtension().lastPathComponent.lowercased()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { url in
            guard url.deletingPathExtension().lastPathComponent.lowercased() == base else { return false }
            let ext = url.pathExtension.lowercased()
            return ext.range(of: #"z\d\d"#, options: .regularExpression) != nil
        }
    }

    private func relatedSevenZipVolumes(for firstVolume: URL) -> [URL] {
        let directory = firstVolume.deletingLastPathComponent()
        let base = firstVolume.deletingPathExtension().lastPathComponent.lowercased()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { url in
            guard url.deletingPathExtension().lastPathComponent.lowercased() == base else { return false }
            let ext = url.pathExtension
            return ext.count == 3 && ext.allSatisfy(\.isNumber)
        }.sorted { $0.pathExtension < $1.pathExtension }
    }

    private func moveOriginalsToTrash(_ urls: [URL]) async throws {
        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle(existingURLs) { _, error in
                if let error {
                    continuation.resume(throwing: ArchiveError.trashFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
