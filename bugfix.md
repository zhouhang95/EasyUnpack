# Bug 修复记录

## 2026-08-22 08:47:34 CST — 分卷 ZIP 中跨最终卷的 MP4 被截断

### 问题表现

- 解压 `体育室.z01`～`体育室.z04`、`体育室.zip` 这套加密分卷 ZIP 时，UI 最终提示解压失败。
- JPG 文件可以正常解压，但最后的 `copy_60016DCF-1F14-4D44-8D20-235ED2C6CAA3.MP4` 无法播放。
- 损坏文件大小为 `1,968,212,655` 字节；ZIP 中记录的正确大小为 `2,052,801,110` 字节，缺少 `84,588,455` 字节。
- `ffprobe` 报错 `moov atom not found`，说明 MP4 尾部元数据没有被写出。

### 根因

该 MP4 从 `.z04` 跨越到了保存中央目录的最终 `.zip` 卷。minizip-ng 的分卷读取流在读完 `.z04` 后固定尝试打开 `.z05`，没有把下一卷映射到标准 ZIP 分卷的最终 `.zip` 文件，因此在分卷边界提前结束读取，留下了一个真实截断的 MP4。

这不是可以忽略的完成状态或 CRC 误报；输出文件确实缺失数据。

### 修复内容

- 解压标准分卷 ZIP 时，在 App 临时目录创建一组符号链接视图。
- 原始 `.z01`～`.z04` 和 `.zip` 数据仍被直接读取，不复制、不拼接压缩包。
- 将最终 `.zip` 额外映射为 minizip-ng 期望的下一数字卷 `.z05`，使跨卷条目能够连续读到最终卷。
- 解压结束后自动删除临时符号链接目录。
- 保留文件大小和 CRC 校验，不能以“文件已生成”为理由忽略真实的数据错误。

### 验证结果

- 修复后 MP4 大小：`2,052,801,110` 字节，与 ZIP 中记录一致。
- CRC32：`88dd384f`，与 ZIP 中记录完全一致。
- `ffprobe` 可正常识别：
  - 视频：H.264，`2160 × 3840`
  - 音频：AAC
  - 时长：约 `320.87` 秒
- Debug 配置构建通过。

## 2026-08-25 01:42:30 CST — 伪装成 ZIP 的 7z AES+Deflate 无法解压

### 问题表现

- 文件 `108 (1).zip` 使用密码 `HHKHHX` 时无法解压，但其他解压软件可以正常处理。
- 文件扩展名为 `.zip`，实际内容签名为标准 7z：`37 7A BC AF 27 1C`。
- 压缩包包含 38 张 JPG，采用 `7zAES + Deflate`，并使用固实压缩。

### 根因

EasyUnpack 已经能够根据内容签名将伪装成 `.zip` 的文件交给 7z 解码器，因此问题不在格式路由。

项目原先使用的 PLzmaSDK 仅包含 7z 的 LZMA、LZMA2 和 PPMd 等解码器。它虽然定义了 Deflate 方法编号 `0x40108`，但没有包含或注册 Deflate 解码器，所以 AES 解密后的 Deflate 数据无法继续解压。

macOS 自带 libarchive 同样不支持该压缩包的加密 7z 目录，不能作为兼容后端。

### 修复内容

- 将 PLzmaSDK 固定为项目内的本地依赖，避免修改 DerivedData 中不可复现的包缓存。
- 在本地 PLzmaSDK 中增加基于系统 zlib 的原始 Deflate 解码器。
- 将解码器注册为 7z Deflate 方法 ID `0x40108`。
- 7z AES 密码验证和解密继续由 7-Zip SDK 完成；解密后的 Deflate 数据直接交给 zlib。
- App 不执行 `7z`、`unar`、`bsdtar` 等外部命令行程序。
- 本地 PLzmaSDK 包显式链接系统 `libz`。

### 验证结果

- 使用密码 `HHKHHX` 成功解出全部 38 张 JPG。
- `1.jpg` 解压后大小为 `701,332` 字节。
- `1.jpg` CRC32 为 `4024328739`，与 7z 目录记录完全一致。
- 抽查输出文件均可识别为有效 JPEG。
- Debug 配置构建通过。

## 2026-09-12 05:00:17 CST — 同名双层 ZIP 无法持续解压

### 问题表现

- 外层 `Sameki -达妮娅 Denia.zip` 只有一个加密条目，解出后文件名为 `Sameki -达妮娅 Denia`，没有扩展名。
- 内层文件的 magic number 是标准 ZIP `50 4B 03 04`，App 已经进入第二层，但随后提示 minizip 错误码 `-116`。
- 两层使用同一个密码。

### 根因

内层 ZIP 的唯一顶层目录也叫 `Sameki -达妮娅 Denia`。递归开始时，无扩展名的内层 ZIP 文件仍占用这个路径，第二层尝试创建同名目录时发生文件与目录冲突。`ZIPArchiveExtractor` 将该文件系统写入异常映射为 `-116`。

此外，将内层文件改名为 `.zip` 后会复用刚刚回收的外层 ZIP 路径。如果最终回收列表不去重，同一路径会被提交给废纸篓 API 两次，导致第二次回收报错。

### 修复内容

- 本层只解出一个普通文件且 magic number 可识别时，先把已经完成的上一层源包及分卷移到废纸篓。
- 根据实际格式把新文件的扩展名改为 `.zip`、`.tar`、`.7z` 或 `.rar`，不依赖原文件名。
- 使用改名后的新归档继续递归解压，并复用当前密码。
- 废纸篓列表按标准化绝对路径去重，避免新旧归档复用同一路径时重复回收。
- 保留最多 32 层的递归限制。

### 验证结果

- 使用原问题文件的临时副本完成两层 ZIP 解压。
- 外层完成后，内层无扩展名文件被正确改名为 `Sameki -达妮娅 Denia.zip`。
- 第二层成功创建 `Sameki -达妮娅 Denia/`，共解出 71 个文件。
- 解压目录中没有残留 ZIP，App 成功自动退出，未再出现 `-116` 或废纸篓错误。
- Debug 配置构建通过，`git diff --check` 通过。

## 2026-11-02 12:52 — 7z 解压速度明显慢于其他解压软件

### 问题表现

- 样本 `课件2873.7z`，`3,374,430,154` 字节，74 个条目，解出 73 个文件、约 3.3 GB。
- 其他解压软件约 30 秒完成，本 App 约 120 秒，CPU 长时间单核跑满。
- 归档为 AES 加密，正确密码下内容可正常解出，不是失败重试或 CRC 反复校验造成的假慢。

### 定位过程

- 用同一份 `Vendor/PLzmaSDK` 写了独立基准程序，把“只解码不写盘”和“带进度回调解压”分开计时。
- 只解码耗时 74 秒、写盘与进度回调合计不到 1 秒，说明瓶颈完全在解码器，不在文件写入、不在进度回调、不在废纸篓。
- `sample` 采样显示 90% 以上样本落在 `LzmaDec_DecodeReal2`（`C/LzmaDec.c` 的纯 C 解码循环）。
- `nm` 检查发现 `Asm/arm64/LzmaDecOpt.S` 的 `LzmaDec_DecodeReal_3` 虽然被编译并链接进库，但 `LzmaDec.c.o` 没有任何引用，汇编解码器实际从未被调用。

### 根因

`LzmaDec.c` 通过 `Z7_LZMA_DEC_OPT` 决定用汇编版还是纯 C 版解码器，而这个宏只在上游 7-Zip 的构建脚本里定义，`Vendor/PLzmaSDK/Package.swift` 没有定义它，因此 ARM64 汇编解码器一直是死代码。

顺带确认同目录还有两处性能设置，但本次未改动：`src/plzma_private.h` 无条件定义 `Z7_ST`，整库按单线程编译；`src/C/AesOpt.c` 在 `LIBPLZMA` 下 undef 掉架构宏，导致硬件 AES 分支被编译成空文件。实测开启硬件 AES 后同一份样本并没有变快（62.5 秒，±12% 机器状态漂移内），因此没有保留该改动。

### 修复内容

- 在 `Vendor/PLzmaSDK/Package.swift` 的 `libplzma` 目标 `cSettings` 中定义 `Z7_LZMA_DEC_OPT=1`，让 `LzmaDec.c` 调用 `Asm/arm64/LzmaDecOpt.S` 的 `LzmaDec_DecodeReal_3`。
- 不改 App 层 Swift 代码，不改解压流程，不改安全检查和输出路径逻辑。

### 验证结果

- `nm` 显示 `LzmaDec.c.o` 出现对 `_LzmaDec_DecodeReal_3` 的未定义引用，由 `LzmaDecOpt.S.o` 提供，确认汇编实现真正生效。
- 同一份样本副本解压产物与改动前逐字节比对一致：73 个文件清单、大小、`diff -r` 全部相同。
- 同一环境下相邻测量：改动前 74.9 秒，改动后 55.6 秒，约快 25%；该机器测速有约 ±12% 的漂移，后续复测为 62 秒量级。
- 用 `Vendor/PLzmaSDK/test_files` 下的样本回归解码，无崩溃、无解压失败（部分样本本身加密，需密码，行为与改动前一致）。
- 本机 `xcodebuild` 因系统 `sandbox_apply` 限制无法完成 SwiftPM 包解析，改用 `swift build -c release/debug --disable-sandbox` 对同一个 `libplzma` 目标做 Release 与 Debug 编译验证，均通过；App 层 Swift 代码本次未改动。
- `git diff --check` 通过。

## 2026-11-02 13:40 — 7z 解压仍然只能跑满单核

### 问题表现

- 启用汇编解码器后同一份 `课件2873.7z` 仍需约 55 秒，而 Bandizip、7-Zip 约 30 秒。
- 采样显示解码期间只有一个线程在跑，其余核心空闲。

### 定位过程

- `src/plzma_private.h` 在 `LIBPLZMA` 下无条件 `#define Z7_ST 1` / `_7ZIP_ST 1`，`CPP/7zip/Compress/Lzma2Decoder.cpp`、`7zExtract.cpp`、`HandlerOut.h` 里所有多线程分支都被编译掉。
- 由此 `CCommonMethodProps::InitCommon()` 不再把 `_numThreads` 初始化为 CPU 核数，POSIX 的 `GetNumberOfProcessors()` 也直接返回 1，解压链路根本没有 MT 入口。
- 去掉 `Z7_ST` 后链接失败：`MtDec_*`、`MtProgress_*`、`CStreamBinder::*` 未定义。PLzmaSDK 为了让库能单线程编译，把 `src/C/MtDec.c` 与 `src/CPP/7zip/Common/StreamBinder.cpp` 从仓库里删掉了，只剩头文件。

### 修复内容

- `src/plzma_private.h`：把 `_7ZIP_ST` / `Z7_ST` 的定义放进 `#if !defined(LIBPLZMA_ENABLE_MT)` 分支，默认行为不变。
- `Vendor/PLzmaSDK/Package.swift`：`libplzma` 的 `cSettings` 与 `cxxSettings` 同时定义 `LIBPLZMA_ENABLE_MT=1`。
- 从 7-Zip 26.00 上游补回 `src/C/MtDec.c` 与 `src/CPP/7zip/Common/StreamBinder.cpp`（与仓库内 `MtDec.h`、`StreamBinder.h` 版本一致；`MtDec.h` 逐行相同，`StreamBinder.h` 仅多一个 `Z7_final` 修饰）。
- 不改 App 层 Swift 代码。线程数由库自身按 CPU 核数与可用内存计算，`CMixerMT` 让 AES 解密与 LZMA2 解码流水并行。

### 验证结果

- 同一份样本：单线程 60.19 秒 / 68.16 秒，多线程 26.43 / 26.53 / 27.41 / 28.18 / 29.80 秒，约 2.1 倍。机器为 Apple A18 Pro（6 核，2 性能核 + 4 能效核），8 GB 内存。
- 正确性：单线程产物与多线程产物 `diff -r` 完全一致，73 个文件清单与大小全部相同；带进度回调（12971 次回调）的多线程产物同样一致。
- 进度回调在 MT 下正常工作，没有卡死或乱序。
- `Vendor/PLzmaSDK/test_files` 下 14 个样本逐一比对单线程版与多线程版：通过/失败的集合完全一致（其中 9 个样本本身在此构建下就无法解码，属既有现象，与本次改动无关）。
- Release 与 Debug 两种配置均编译通过。
- 本机 `xcodebuild` 仍因 `sandbox_apply` 限制无法完成 SwiftPM 包解析，验证改用 `swift build --disable-sandbox`。
