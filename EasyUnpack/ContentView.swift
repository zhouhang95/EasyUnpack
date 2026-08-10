//
//  ContentView.swift
//  EasyUnpack
//
//  Created by ZhouHang on 2026/8/10.
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: ExtractionViewModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                Text(isDropTargeted ? "松开以添加压缩文件" : "将压缩文件拖到这里")
                    .font(.headline)
                Text(model.sourceURLs.isEmpty ? "支持 ZIP、TAR、7z、RAR 及分卷" : model.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            )
            .dropDestination(for: URL.self) { urls, _ in
                model.acceptDroppedFiles(urls)
                return !urls.isEmpty
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }

            GroupBox("密码（可选）") {
                TextField("未加密则留空", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .padding(6)
            }

            if let message = model.message {
                Label(message, systemImage: model.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(model.isError ? .red : .green)
                    .textSelection(.enabled)
            }

            if model.isExtracting {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: model.extractionProgress)
                    Text("正在解压 \(Int(model.extractionProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("解压到当前目录，成功后原压缩文件将移到废纸篓")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.extract()
                } label: {
                    if model.isExtracting { ProgressView().controlSize(.small) }
                    else { Text("开始解压") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.sourceURLs.isEmpty || model.isExtracting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

#Preview {
    ContentView(model: ExtractionViewModel())
}
