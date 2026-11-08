# ZIP 性能测试

`benchmark-zip.swift` 直接调用应用的 `ZIPArchiveExtractor`，不调用递归服务或废纸篓操作。它会写入指定输出目录，须使用独立测试目录，不能指定有重要文件的目录。使用 Release 的 `ZipArchive.o` 并以 `swiftc -O` 编译，保留正常密码验证和条目 CRC 检查。

示例（先完成 Release 构建，将 build_root 设为该次 Xcode 构建的 Build 目录）：

```bash
xcrun swiftc -O -parse-as-library \
  -I "$build_root/Products/Release" \
  -Xcc -fmodule-map-file="$build_root/Intermediates.noindex/GeneratedModuleMaps/ZipArchive.modulemap" \
  EasyUnpack/Archive/ArchiveModels.swift EasyUnpack/Archive/ZIPArchiveExtractor.swift \
  Tests/benchmark-zip.swift "$build_root/Products/Release/ZipArchive.o" \
  -lz -liconv -framework Security -o /tmp/easyunpack-zip-benchmark
/tmp/easyunpack-zip-benchmark /path/to/archive.zip /path/to/test-output 'password'
```

- 每次完整执行后输出 `ELAPSED`，时间包含目录解析、解密、解压、输出写入和 CRC 验证，不包含构建、UI 和事后的 SHA-256 对比。
- 基线与优化版按顺序执行，复用相同测试目录，避免同时占用多份大文件输出。
- 对所有输出文件记录 SHA-256，优化后逐个比对。任何解码、密码或 CRC 错误均返回非零退出码。
