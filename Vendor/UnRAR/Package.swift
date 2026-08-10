// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnRAR",
    products: [.library(name: "CUnRAR", targets: ["CUnRAR"])],
    targets: [
        .target(
            name: "CUnRAR",
            path: ".",
            sources: [
                "strlist.cpp", "strfn.cpp", "pathfn.cpp", "smallfn.cpp", "global.cpp",
                "file.cpp", "filefn.cpp", "filcreat.cpp", "archive.cpp", "arcread.cpp",
                "unicode.cpp", "system.cpp", "crypt.cpp", "crc.cpp", "rawread.cpp",
                "encname.cpp", "resource.cpp", "match.cpp", "timefn.cpp", "rdwrfn.cpp",
                "consio.cpp", "options.cpp", "errhnd.cpp", "rarvm.cpp", "secpassword.cpp",
                "rijndael.cpp", "getbits.cpp", "sha1.cpp", "sha256.cpp", "blake2s.cpp",
                "hash.cpp", "extinfo.cpp", "extract.cpp", "volume.cpp", "list.cpp",
                "find.cpp", "unpack.cpp", "headers.cpp", "threadpool.cpp", "rs16.cpp",
                "cmddata.cpp", "ui.cpp", "largepage.cpp", "filestr.cpp", "scantree.cpp",
                "dll.cpp", "qopen.cpp"
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .define("RARDLL"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_LARGEFILE_SOURCE"),
                .define("RAR_SMP"),
                .unsafeFlags(["-Wno-logical-op-parentheses", "-Wno-switch", "-Wno-dangling-else"])
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
