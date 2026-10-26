// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AICronHelper",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 自动更新；固定版本，升级前先看 release notes
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "AICronHelper",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/AICronHelper",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "AICronHelperTests",
            dependencies: ["AICronHelper"],
            path: "Tests/AICronHelperTests"
        ),
    ]
)
