import Foundation

final class Reporter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ContinuousClock.now
    func report(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        let now = ContinuousClock.now
        if last.duration(to: now) >= .seconds(10) || value == 1 {
            print("PROGRESS \(value)")
            fflush(stdout)
            last = now
        }
    }
}

@main struct Benchmark {
    static func main() async {
        do {
        let args = CommandLine.arguments
        let reporter = Reporter()
        let start = ContinuousClock.now
        let request = ArchiveRequest(
            sourceURLs: [URL(fileURLWithPath: args[1])],
            destinationURL: URL(fileURLWithPath: args[2]),
            password: args[3],
            progress: { reporter.report($0) }
        )
        let result = try await ZIPArchiveExtractor().extract(request)
        print("ELAPSED \(start.duration(to: .now)) OUTPUT \(result.destinationURL.path)")
        } catch {
            print("FAILED \(error.localizedDescription)")
            exit(1)
        }
    }
}
