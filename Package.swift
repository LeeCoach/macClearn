// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacCleaner", targets: ["MacCleaner"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacCleaner",
            path: "MacCleaner",
            exclude: ["Info.plist", "Resources"],
            swiftSettings: [
                // CI（Xcode 15+/Swift 6）默认语言模式会把并发相关诊断当错误；保持 Swift 5 模式与本地一致
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "MacCleaner/Info.plist"
                ])
            ]
        )
    ]
)
