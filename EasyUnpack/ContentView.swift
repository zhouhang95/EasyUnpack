//
//  ContentView.swift
//  EasyUnpack
//
//  Created by ZhouHang on 2026/8/10.
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: ExtractionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("压缩文件") {
                HStack {
                    Text(model.sourceSummary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("选择…") { model.chooseSources() }
                }.padding(6)
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
