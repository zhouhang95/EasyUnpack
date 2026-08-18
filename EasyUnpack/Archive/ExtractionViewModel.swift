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
    var elapsedSeconds = 0
    var message: String?
    var isError = false

    private let service = ArchiveService()
    @ObservationIgnored private var didReadPasteboard = false
    @ObservationIgnored private var elapsedTask: Task<Void, Never>?

    var sourceSummary: String {
        guard !sourceURLs.isEmpty else { return "尚未选择" }
        if sourceURLs.count == 1 { return sourceURLs[0].lastPathComponent }
        return "\(sourceURLs.first(where: { $0.pathExtension.lowercased() == "zip" })?.lastPathComponent ?? sourceURLs[0].lastPathComponent) 等 \(sourceURLs.count) 个分卷"
    }

    var archiveDirectory: URL? {
        let mainArchive = sourceURLs.first(where: { $0.pathExtension.lowercased() == "zip" }) ?? sourceURLs.first
        return mainArchive?.deletingLastPathComponent()
    }

    var elapsedText: String {
        let hours = elapsedSeconds / 3600
        let minutes = elapsedSeconds % 3600 / 60
        let seconds = elapsedSeconds % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
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
        acceptFiles(urls, autoExtract: true)
    }

    func acceptDroppedFiles(_ urls: [URL]) {
        acceptFiles(urls, autoExtract: false)
    }

    private func acceptFiles(_ urls: [URL], autoExtract: Bool) {
        var archiveURLs = urls.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            let ext = url.pathExtension.lowercased()
            return ArchiveFormatDetector.detect(url) != nil || ext == "001" ||
                ext.range(of: #"[zr]\d\d"#, options: .regularExpression) != nil
        }
        guard !archiveURLs.isEmpty else {
            isError = true
            message = "拖入的文件不是受支持的 ZIP、TAR、7z 或 RAR 文件。"
            return
        }

        if let main = archiveURLs.first(where: { ArchiveFormatDetector.detect($0) == .zip }) {
            archiveURLs = Array(Set(archiveURLs + relatedVolumes(for: main)))
        } else if let firstVolume = archiveURLs.first(where: {
            ArchiveFormatDetector.detect($0) == .sevenZ || $0.pathExtension == "001"
        }) {
            archiveURLs = Array(Set(archiveURLs + relatedSevenZipVolumes(for: firstVolume)))
        } else if let mainRAR = archiveURLs.first(where: { ArchiveFormatDetector.detect($0) == .rar }) {
            archiveURLs = Array(Set(archiveURLs + relatedRARVolumes(for: mainRAR)))
        }

        let openedBase = archiveURLs[0].deletingPathExtension().path
        let matchingExisting = sourceURLs.filter { $0.deletingPathExtension().path == openedBase }
        let combined = Dictionary(
            (matchingExisting + archiveURLs).map { ($0.path, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        sourceURLs = Array(combined.values).sorted { lhs, rhs in
            if lhs.pathExtension.lowercased() == "zip" { return false }
            if rhs.pathExtension.lowercased() == "zip" { return true }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
        destinationURL = archiveDirectory
        isError = false
        message = autoExtract ? "已从 Finder 接收文件，将解压到压缩包所在目录。" : nil

        if autoExtract, sourceURLs.contains(where: {
            ArchiveFormatDetector.detect($0) != nil || $0.pathExtension.lowercased() == "001"
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
            UTType(filenameExtension: "rar") ?? .data,
            .data
        ]
        guard panel.runModal() == .OK else { return }
        acceptFiles(panel.urls, autoExtract: false)
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
        startElapsedTimer()
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
                if let archiveError = error as? ArchiveError,
                   case .invalidPassword = archiveError {
                    password = ""
                }
                isError = true
                message = error.localizedDescription
            }
            isExtracting = false
            elapsedTask?.cancel()
            elapsedTask = nil
            extractionProgress = 0
        }
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        elapsedSeconds = 0
        elapsedTask = Task { @MainActor [self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                elapsedSeconds += 1
            }
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

    private func relatedRARVolumes(for main: URL) -> [URL] {
        let directory = main.deletingLastPathComponent()
        let lowerName = main.lastPathComponent.lowercased()
        let partRange = lowerName.range(of: #"\.part\d+\.rar$"#, options: .regularExpression)
        let base = partRange.map { String(lowerName[..<$0.lowerBound]) }
            ?? main.deletingPathExtension().lastPathComponent.lowercased()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { url in
            let name = url.lastPathComponent.lowercased()
            if partRange != nil {
                return name.range(of: "^\(NSRegularExpression.escapedPattern(for: base))\\.part\\d+\\.rar$", options: .regularExpression) != nil
            }
            let ext = url.pathExtension.lowercased()
            return url.deletingPathExtension().lastPathComponent.lowercased() == base &&
                (ext == "rar" || ext.range(of: #"r\d\d"#, options: .regularExpression) != nil)
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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
