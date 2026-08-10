//
//  EasyUnpackApp.swift
//  EasyUnpack
//
//  Created by ZhouHang on 2026/8/10.
//

import AppKit
import SwiftUI

@main
struct EasyUnpackApp: App {
    @State private var model = ExtractionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    model.loadPasswordFromPasteboardIfNeeded()
                }
                .onOpenURL { url in
                    model.acceptOpenedFiles([url])
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("选择压缩文件…") { model.chooseSources() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
