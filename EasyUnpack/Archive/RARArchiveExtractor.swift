import CUnRAR
import Foundation

nonisolated private final class RARCallbackContext: @unchecked Sendable {
    let password: [UInt8]
    let widePassword: [UInt32]
    let total: UInt64
    let report: (@Sendable (Double) -> Void)?
    private let lock = NSLock()
    private var processed: UInt64 = 0

    init(password: String?, total: UInt64, report: (@Sendable (Double) -> Void)?) {
        self.password = Array((password ?? "").utf8) + [0]
        self.widePassword = (password ?? "").unicodeScalars.map(\.value) + [0]
        self.total = max(total, 1)
        self.report = report
    }

    func add(_ count: Int) {
        lock.lock()
        processed += UInt64(max(count, 0))
        let value = min(Double(processed) / Double(total), 0.99)
        lock.unlock()
        report?(value)
    }
}

nonisolated private let easyUnpackRARCallback: @convention(c) (UInt32, Int, Int, Int) -> Int32 = {
    message, userData, parameter1, parameter2 in
    let context = Unmanaged<RARCallbackContext>.fromOpaque(UnsafeRawPointer(bitPattern: userData)!).takeUnretainedValue()
    switch UNRARCALLBACK_MESSAGES(rawValue: message) {
    case UCM_PROCESSDATA:
        context.add(parameter2)
        return 1
    case UCM_NEEDPASSWORD:
        guard parameter1 != 0, parameter2 > 0 else { return -1 }
        let target = UnsafeMutablePointer<UInt8>(bitPattern: parameter1)!
        let count = min(context.password.count, parameter2)
        target.update(from: context.password, count: count)
        target[count - 1] = 0
        return 1
    case UCM_NEEDPASSWORDW:
        guard parameter1 != 0, parameter2 > 0 else { return -1 }
        let target = UnsafeMutablePointer<UInt32>(bitPattern: parameter1)!
        let count = min(context.widePassword.count, parameter2)
        target.update(from: context.widePassword, count: count)
        target[count - 1] = 0
        return 1
    default:
        return 1
    }
}

struct RARArchiveExtractor: ArchiveExtractor {
    nonisolated let format: ArchiveFormat = .rar

    nonisolated func canHandle(_ urls: [URL]) -> Bool {
        urls.contains { ArchiveFormatDetector.detect($0) == .rar }
    }

    nonisolated func extract(_ request: ArchiveRequest) async throws -> ArchiveResult {
        try await Task.detached(priority: .userInitiated) { try extractSynchronously(request) }.value
    }

    nonisolated private func extractSynchronously(_ request: ArchiveRequest) throws -> ArchiveResult {
        guard let source = firstRAR(in: request.sourceURLs) else { throw ArchiveError.noSource }
        let scoped = request.sourceURLs + [request.destinationURL]
        let accessed = scoped.map { $0.startAccessingSecurityScopedResource() }
        defer {
            for (url, didAccess) in zip(scoped, accessed) where didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let listed = try list(source, password: request.password)
        let roots = Set(listed.paths.compactMap { safeComponents($0)?.first }).subtracting(["__MACOSX"])
        let destination = roots.count > 1
            ? request.destinationURL.appendingPathComponent(archiveBaseName(source), isDirectory: true)
            : request.destinationURL
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try unpack(source, to: destination, password: request.password, total: listed.total, progress: request.progress)
        let metadata = destination.appendingPathComponent("__MACOSX", isDirectory: true)
        if FileManager.default.fileExists(atPath: metadata.path) { try FileManager.default.removeItem(at: metadata) }
        request.progress?(1)
        return ArchiveResult(
            destinationURL: destination,
            format: format,
            topLevelURLs: roots.map { destination.appendingPathComponent($0) }
        )
    }

    nonisolated private func list(_ source: URL, password: String?) throws -> (paths: [String], total: UInt64) {
        let context = RARCallbackContext(password: password, total: 1, report: nil)
        let handle = try open(source, mode: UInt32(RAR_OM_LIST), context: context)
        defer { _ = RARCloseArchive(handle) }
        var paths: [String] = []
        var total: UInt64 = 0
        while true {
            var header = RARHeaderDataEx()
            let result = RARReadHeaderEx(handle, &header)
            if result == ERAR_END_ARCHIVE { break }
            try check(result)
            let path = withUnsafeBytes(of: header.FileName) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            guard safeComponents(path) != nil else {
                throw ArchiveError.extractionFailed("RAR 包含不安全的文件路径：\(path)")
            }
            paths.append(path)
            total += UInt64(header.UnpSize) | UInt64(header.UnpSizeHigh) << 32
            try check(RARProcessFile(handle, RAR_SKIP, nil, nil))
        }
        return (paths, total)
    }

    nonisolated private func unpack(
        _ source: URL, to destination: URL, password: String?, total: UInt64,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        let context = RARCallbackContext(password: password, total: total, report: progress)
        let handle = try open(source, mode: UInt32(RAR_OM_EXTRACT), context: context)
        defer { _ = RARCloseArchive(handle) }
        while true {
            var header = RARHeaderDataEx()
            let result = RARReadHeaderEx(handle, &header)
            if result == ERAR_END_ARCHIVE { break }
            try check(result)
            let path = withUnsafeBytes(of: header.FileName) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            let operation = safeComponents(path)?.first == "__MACOSX" ? RAR_SKIP : RAR_EXTRACT
            let resultCode = destination.path.withCString { destinationPointer in
                RARProcessFile(handle, operation, UnsafeMutablePointer(mutating: destinationPointer), nil)
            }
            try check(resultCode)
        }
    }

    nonisolated private func open(_ source: URL, mode: UInt32, context: RARCallbackContext) throws -> UnsafeMutableRawPointer {
        let unmanaged = Unmanaged.passUnretained(context)
        var data = RAROpenArchiveDataEx()
        data.OpenMode = mode
        data.Callback = easyUnpackRARCallback
        data.UserData = Int(bitPattern: unmanaged.toOpaque())
        let handle = source.path.withCString { pointer -> UnsafeMutableRawPointer? in
            data.ArcName = UnsafeMutablePointer(mutating: pointer)
            return RAROpenArchiveEx(&data)
        }
        guard let handle else { throw ArchiveError.damagedArchive }
        try check(Int32(data.OpenResult))
        if context.password.count > 1 {
            context.password.withUnsafeBufferPointer { pointer in
                RARSetPassword(handle, UnsafeMutablePointer(mutating: pointer.baseAddress).map {
                    UnsafeMutableRawPointer($0).assumingMemoryBound(to: CChar.self)
                })
            }
        }
        return handle
    }

    nonisolated private func check(_ code: Int32) throws {
        switch code {
        case ERAR_SUCCESS: return
        case ERAR_MISSING_PASSWORD, ERAR_BAD_PASSWORD:
            NSLog("EasyUnpack UnRAR returned password error %d", code)
            throw ArchiveError.invalidPassword
        case ERAR_BAD_DATA, ERAR_BAD_ARCHIVE, ERAR_UNKNOWN_FORMAT:
            NSLog("EasyUnpack UnRAR returned archive error %d", code)
            throw ArchiveError.damagedArchive
        default:
            NSLog("EasyUnpack UnRAR returned error %d", code)
            throw ArchiveError.extractionFailed("RAR 解压失败（UnRAR 错误码 \(code)）。")
        }
    }

    nonisolated private func firstRAR(in urls: [URL]) -> URL? {
        let rarFiles = urls.filter { ArchiveFormatDetector.detect($0) == .rar || $0.pathExtension.lowercased() == "rar" }
        return rarFiles.first(where: { $0.lastPathComponent.range(of: #"\.part0*1\.rar$"#, options: [.regularExpression, .caseInsensitive]) != nil })
            ?? rarFiles.first
    }

    nonisolated private func archiveBaseName(_ source: URL) -> String {
        source.deletingPathExtension().lastPathComponent.replacingOccurrences(
            of: #"\.part0*1$"#, with: "", options: [.regularExpression, .caseInsensitive]
        )
    }

    nonisolated private func safeComponents(_ path: String) -> [String]? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { return nil }
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        return parts
    }
}
