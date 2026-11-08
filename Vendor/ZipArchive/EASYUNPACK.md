# EasyUnpack 本地 ZIP 依赖

- 来源：https://github.com/ZipArchive/ZipArchive
- 基础 revision：`df35718ea19a94e015b91dc4881dee028ce4cdba`
- 保留上游 `Package.swift`、`SSZipArchive` 和 `LICENSE.txt`。
- 定制文件：`SSZipArchive/minizip/mz_strm_pkcrypt.c`。
- 将 ZipCrypto 密钥更新中的单字节 CRC 函数调用替换为相同多项式 `0xedb88320` 的不可变查表计算。保留密码校验、数据 CRC 校验、AES、ZIP64 和分卷读取逻辑。
- 更新依赖时需迁移此优化，并验证正确密码、错误密码、空密码和大文件输出 CRC。
