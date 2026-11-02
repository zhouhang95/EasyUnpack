// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PLzmaSDK",
    products: [
        .library(name: "PLzmaSDK", targets: ["PLzmaSDK"]),
        .library(name: "PLzmaSDK-Static", type: .static, targets: ["PLzmaSDK"]),
        .library(name: "PLzmaSDK-Dynamic", type: .dynamic, targets: ["PLzmaSDK"])
    ],
    targets: [
        .target(name: "libplzma",
                path: "src",
                cSettings: [
                    .define("LIBPLZMA_VERSION_BUILD", to: "1420"),
                    // EasyUnpack: 启用 Asm/arm64/LzmaDecOpt.S 中的汇编解码器
                    // (LzmaDec_DecodeReal_3)。不定义时 LzmaDec.c 会退回纯 C 版
                    // LzmaDec_DecodeReal2，7z 解压速度约慢 20%~25%。
                    .define("Z7_LZMA_DEC_OPT", to: "1"),
                    // EasyUnpack: 启用 7-Zip 多线程编解码（Lzma2DecMt）。
                    // 不定义时 plzma_private.h 会强制 Z7_ST，整库按单线程编译，
                    // 解压只能跑满一个核。
                    .define("LIBPLZMA_ENABLE_MT", to: "1"),
                    .unsafeFlags(["-fPIC"])
                ],
                cxxSettings: [
                    .define("LIBPLZMA_VERSION_BUILD", to: "1420"),
                    .define("LIBPLZMA_ENABLE_MT", to: "1"),
                    .unsafeFlags(["-fPIC", "-fno-rtti"])
                ],
                linkerSettings: [.linkedLibrary("z")]),
        .target(name: "PLzmaSDK",
                dependencies: [
                    .target(name: "libplzma")
                ],
                path: "swift",
                resources: [
                    .copy("../resources/PrivacyInfo.xcprivacy"),
                ]),
        .target(name: "plzma_test_files",
                path: "test_files",
                cSettings: [
                    .unsafeFlags(["-fPIC"])
                ],
                cxxSettings: [
                    .unsafeFlags(["-fPIC", "-fno-rtti"])
                ]),
        .testTarget(
            name: "PLzmaSDKTests",
            dependencies: [
                .target(name: "PLzmaSDK"),
                .target(name: "libplzma"),
                .target(name: "plzma_test_files")
            ],
            path: "swift_pm_tests")
    ],
    swiftLanguageModes: [.v5, .v6],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx11
)
