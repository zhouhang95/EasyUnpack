# EasyUnpack 项目指南

## 1. 项目定位

EasyUnpack 是原生 macOS SwiftUI 解压工具。它通过 Finder“打开方式”、拖放或菜单选择接收文件，直接在 App 进程内解析归档，不调用 `unzip`、`7z`、`unar`、`bsdtar` 等外部程序。

当前支持 ZIP、TAR、7z、RAR、密码和常见分卷。格式判断优先使用文件内容签名，不信任扩展名，因此也要支持伪装格式及 ZIP 前附加 PNG 等普通数据的文件。

## 2. 不得随意改变的产品行为

1. 始终解压到压缩包所在目录，不弹出目标目录选择 UI。
2. Finder 打开文件时自动解压；拖入或菜单选择文件时由用户点击开始。
3. 归档根目录有多个顶层项时，新建与压缩包同名的目录；只有一个顶层项时直接解压到当前目录。
4. 跳过并清理根部 `__MACOSX` 目录。
5. 密码框明文显示。App 第一次显示时，如果剪贴板是纯文本且不是文件 URL，就自动填入密码框。
6. 密码错误后清空密码框。
7. 文件直接写入最终可见目录；解压期间持续更新进度和已用时间，不能先写入隐藏临时目录再整体移动。
8. 解压成功后自动退出，并把全部源压缩文件或分卷移到废纸篓；失败时保留 App、错误信息和源文件。
9. 如果本层只解出一个普通文件，且其 magic number 能识别为支持的归档格式，则复用当前密码继续递归解压；全部成功后同时回收中间归档。

> **测试警告：** 成功解压会自动把源文件移到废纸篓。测试真实样本前必须先复制一份，不能直接使用用户唯一的原包。

## 3. 构建现状

- 工程：`EasyUnpack.xcodeproj`
- Target / Scheme：`EasyUnpack`
- Bundle ID：`zhouhang.EasyUnpack`
- 版本：`1.0 (2)`
- 最低系统版本：macOS `26.4`
- App Sandbox：关闭
- Scheme 的 Run、Profile、Archive 使用 Release；Analyze 使用 Debug
- 当前没有 App 测试 Target

常用命令：

```bash
xcodebuild -project EasyUnpack.xcodeproj -scheme EasyUnpack -configuration Debug build
xcodebuild -project EasyUnpack.xcodeproj -scheme EasyUnpack -configuration Release build
xcodebuild -project EasyUnpack.xcodeproj -scheme EasyUnpack -configuration Release archive
```

Release 没有硬编码 `ARCHS`。实际产物架构由 Xcode 目标和依赖共同决定；发布前用 `lipo -info` 检查，不能只凭“Release”判断是否为 Universal。

## 4. 目录职责

```text
EasyUnpack/
├── EasyUnpack.xcodeproj/            工程、共享 Scheme、SwiftPM 锁文件
├── EasyUnpack/
│   ├── EasyUnpackApp.swift          App 入口、Finder onOpenURL、剪贴板初始化
│   ├── ContentView.swift            拖放、密码、进度、耗时和操作按钮
│   └── Archive/
│       ├── ArchiveModels.swift      格式检测、请求/结果/错误、Extractor 协议
│       ├── ArchiveService.swift     选择具体解压器
│       ├── ExtractionViewModel.swift 文件接收、分卷发现、状态、计时、废纸篓
│       ├── ZIPArchiveExtractor.swift
│       ├── TARArchiveExtractor.swift
│       ├── SevenZipArchiveExtractor.swift
│       └── RARArchiveExtractor.swift
├── Vendor/PLzmaSDK/                 本地且已定制的 7z 库
├── Vendor/UnRAR/                    本地 UnRAR Swift Package
├── Info.plist                       Finder 文件关联和 .001 UTType
└── bugfix.md                        复杂兼容问题及验证记录
```

工程使用 Xcode 文件系统同步组，新增 Swift 文件通常无需手工写入 `PBXSourcesBuildPhase`，但仍须构建确认已被 Target 收录。

## 5. 架构与数据流

### 输入和状态

`ExtractionViewModel` 是 `@MainActor @Observable` 对象，负责接收 Finder、拖放和 `NSOpenPanel` 文件，扫描同目录分卷，创建 `ArchiveRequest`，更新 UI 状态，以及在成功后调用 `NSWorkspace.recycle` 并退出。

各解压器通过 `Task.detached(priority: .userInitiated)` 执行同步解码，避免阻塞主线程。进度回调可能来自后台线程，UI 更新必须切回 `MainActor`。C/C++ 回调上下文使用 `@unchecked Sendable` 和锁；修改时必须保证回调对象及密码缓冲区活到原生调用结束。

### 格式识别和扩展

`ArchiveFormatDetector` 检查：

- `37 7A BC AF 27 1C`：7z
- `Rar! 1A 07`：RAR
- ZIP 本地文件头、EOCD 或 ZIP64 EOCD：ZIP
- TAR 偏移 257 的 `ustar`：TAR

`ArchiveService` 当前按 ZIP、TAR、7z、RAR 的顺序询问 `canHandle`。增加格式时，应新增 `ArchiveFormat`、签名检测和独立 `ArchiveExtractor`，再注册到服务中，不要把新格式混入已有解压器。

`ArchiveService` 还负责自动解压单一内层归档。每层解压器通过 `ArchiveResult.topLevelURLs` 返回真实顶层输出；只有恰好一个普通文件且内容签名可识别时才进入下一层。递归上限为 32 层，并用标准化路径防止重复循环。中间归档只有在整个流程成功后才与最外层源文件一起移到废纸篓。

## 6. 格式实现要点

### ZIP

ZIP 使用远程 Swift Package `ZipArchive` 内的 minizip/minizip-ng C API，`Package.resolved` 固定 revision `df35718ea19a94e015b91dc4881dee028ce4cdba`。这里不是简单调用 Swift 高层 API，现有兼容代码包括：

- 普通 ZIP、ZipCrypto、WinZip AES。
- 标准 `.z01`、`.z02` … `.zip` 分卷。
- `.zip.001`、`.zip.002` 等顺序字节分卷。
- ZIP 前拼接普通数据的嵌入式/SFX 文件，通过 EOCD 推算真实偏移。
- `OffsetZIPStream` 把多个物理文件呈现为逻辑数据流，不先拼接临时大文件。
- Unicode Path Extra Field，以及中文、日文、韩文旧编码文件名。
- 密码按 UTF-8、GB18030、Shift-JIS、CP949 依次尝试。
- 解压前读取中央目录，计算顶层项、总大小、条目大小和 CRC。
- 流式写入最终目录，并拦截绝对路径、`.` 和 `..`。

标准分卷有关键兼容措施：minizip-ng 可能在最后 `.zNN` 后寻找下一个数字卷，而标准最终卷名是 `.zip`。`splitArchiveAliases` 会建立临时符号链接，把最终 `.zip` 映射成下一个 `.zNN`，以支持跨最终卷的大文件。不要删除此逻辑。

部分有效分卷在最终条目完整写出后仍返回 zlib `-3`。当前仅在文件大小和 CRC32 都与中央目录一致时接受结果；不得降低为“文件存在”即成功。

### TAR

TAR 由项目用 `FileHandle` 直接解析，支持普通文件、目录、GNU long name、PAX path、符号链接和硬链接，并保留权限与修改时间。链接目标必须留在解压根目录，路径安全检查不可移除。

### 7z

7z 使用本地 `Vendor/PLzmaSDK`：

- 支持普通和 AES 加密 7z，以及 `.7z.001` 顺序分卷。
- 除原有 LZMA、LZMA2、PPMd 外，项目新增 `DeflateDecoder.h/.cpp` 和 `DeflateRegister.cpp`。
- 自定义解码器使用系统 zlib，并注册 7z Method ID `0x40108`。
- `Vendor/PLzmaSDK/Package.swift` 显式链接 `libz`。

此定制用于 `7zAES + Deflate` 固实包。升级或替换 PLzmaSDK 时必须迁移并验证它，否则伪装成 ZIP 的此类 7z 会回归失败。

### RAR

RAR 使用本地 `Vendor/UnRAR`，Swift 模块名为 `CUnRAR`。实现先列目录再解压，支持密码回调、UTF-8/Unicode 密码、`.partNN.rar` 及旧式 `.rar + .r00` 分卷，并通过数据回调报告进度。

密码缓冲区由 `RARCallbackContext` 长期持有。不要保存生命周期不足的临时 `withCString` 指针。

## 7. Finder 集成与分卷发现

`Info.plist` 以 Viewer、`LSHandlerRank = Alternate` 注册：

- 接受 `public.data` 和通配扩展名，让 Finder 可把任意普通文件交给 App 后再检测内容。
- 另行声明 ZIP、TAR、7z、RAR。
- 为 `.001` 导出 `zhouhang.easyunpack.7z-volume` UTType。

修改关联后 Finder 菜单可能不会立即刷新。应检查构建产物的实际 `Info.plist`，并在需要时重新运行 App 或刷新 Launch Services 注册。

分卷发现规则位于 `ExtractionViewModel`：

- ZIP：同 basename 的 `.zNN` 和最终 `.zip`。
- 7z/顺序块：同 basename 的 `.001`、`.002`……，扩展名必须为连续三位数字。
- RAR：`.partNN.rar`，或旧式 `.rar`、`.r00`、`.r01`……。

解压器内部仍须验证顺序和缺卷情况，不能只信任 UI 层列表，因为 Finder 可能只打开任意一个分卷。

## 8. 安全和正确性约束

- 所有条目必须拒绝绝对路径、`.`、`..` 及逃出目标根目录的链接，防止路径穿越。
- 明确的内容签名优先于扩展名，例如名为 `.zip` 的 7z 必须交给 7z 解压器。
- 只有能确认密码问题时才返回 `invalidPassword`，否则不要误导用户。
- 真正完成前进度最多报告 `0.99`，成功返回前再报告 `1`。
- 大文件必须流式读取和写入，不能整包或整条目载入内存。
- 不得把分卷永久拼接到磁盘；当前 ZIP 和 7z 使用逻辑流组合。
- 已生成文件不等于解压成功，成功判定要依据解码状态、大小和必要的 CRC。
- 若文件已解压但移入废纸篓失败，应明确报错，不能无提示退出。

## 9. 开发和验证

每次修改至少执行：

```bash
xcodebuild -project EasyUnpack.xcodeproj -scheme EasyUnpack -configuration Debug build
git diff --check
```

涉及发布或原生依赖时再跑 Release。格式兼容修改应使用真实问题样本的副本验证：

1. 内容是否路由到正确解压器。
2. Finder 只打开一个分卷时能否找到其余分卷。
3. 正确密码、错误密码和非 UTF-8 密码是否符合预期。
4. 单个/多个顶层项的输出目录是否正确。
5. 解压期间文件是否即时可见，进度和耗时是否持续更新。
6. 大文件跨卷后的大小、CRC 或媒体可解析性是否正确。
7. 成功后源副本是否进废纸篓，失败时是否保留。
8. 路径穿越、外部链接和 `__MACOSX` 是否正确处理。

仓库没有自动化测试 Target，不能把“构建通过”等同于兼容性验证。复杂 Bug 修复后，在 `bugfix.md` 用中文记录时间、样本特征、症状、根因、修改和验证结果；涉及隐私的路径或密码应按需脱敏。

## 10. 依赖管理

- `ZipArchive` 是唯一远程 SwiftPM 依赖。出现 `Missing package product 'ZipArchive'` 时先检查包解析和网络，不要把它误认为系统库。
- `PLzmaSDK` 和 `UnRAR` 是仓库内本地 Package，路径写在 `project.pbxproj`；不要改为 DerivedData 缓存路径。
- 修改 `Vendor` 后同时验证 Debug 和 Release，C/C++ 优化可能暴露不同问题。
- 更新 UnRAR 时遵守 `Vendor/UnRAR/license.txt`；其他第三方库也须保留许可证。
- 不要编辑或提交个人 `xcuserdata`；共享 Scheme 位于 `xcshareddata/xcschemes/EasyUnpack.xcscheme`。

## 11. 提交前检查

- [ ] 未引入外部命令行解压依赖。
- [ ] 未改变当前目录解压、成功后回收原包并退出的约定。
- [ ] UI 主线程未被同步解码阻塞。
- [ ] 进度和耗时持续更新，输出即时可见。
- [ ] 路径和链接安全检查仍有效。
- [ ] 分卷连续性、最终卷别名及数据完整性检查仍有效。
- [ ] 使用源包副本完成对应格式测试。
- [ ] Debug 构建通过；涉及发布或依赖时 Release 也通过。
- [ ] `git diff --check` 无空白错误。
- [ ] 复杂修复已补充到 `bugfix.md`。
