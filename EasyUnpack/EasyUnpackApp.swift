import AppKit
import SwiftUI

@main
struct EasyUnpackApp: App {
    @NSApplicationDelegateAdaptor(UnpackAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .newItem) {
                    Button("选择压缩文件…") { delegate.chooseSources() }
                        .keyboardShortcut("o", modifiers: .command)
                }
            }
    }
}

@MainActor
final class UnpackAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [NSWindow: ExtractionViewModel] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if windows.isEmpty { _ = makeWindow() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let existing = windows.first(where: { $0.value.sourceURLs.contains(url) }) {
                existing.key.makeKeyAndOrderFront(nil)
                continue
            }
            let (window, model): (NSWindow, ExtractionViewModel)
            if let idle = windows.first(where: {
                !$0.value.isExtracting && $0.value.sourceURLs.isEmpty
            }) {
                (window, model) = (idle.key, idle.value)
            } else {
                (window, model) = makeWindow()
            }
            window.title = url.lastPathComponent
            model.acceptOpenedFiles([url])
        }
        application.activate(ignoringOtherApps: true)
    }

    func chooseSources() {
        if let window = NSApp.keyWindow, let model = windows[window], !model.isExtracting {
            model.chooseSources()
        } else {
            makeWindow().1.chooseSources()
        }
    }

    @discardableResult
    private func makeWindow() -> (NSWindow, ExtractionViewModel) {
        let model = ExtractionViewModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "EasyUnpack"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        model.onExtractionSucceeded = { [weak window] in window?.close() }
        windows[window] = model
        window.center()
        window.makeKeyAndOrderFront(nil)
        return (window, model)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeValue(forKey: window)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
