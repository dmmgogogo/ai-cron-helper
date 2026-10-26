// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AICronHelper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AICronHelper",
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
