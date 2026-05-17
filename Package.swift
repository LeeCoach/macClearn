// swift-tools-version: 5.8

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
            exclude: ["Info.plist", "Resources"]
        )
    ]
)
