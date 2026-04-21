// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeCodeUsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeUsageBarCore"
        ),
        .executableTarget(
            name: "ClaudeCodeUsageBar",
            dependencies: ["ClaudeUsageBarCore"]
        ),
        .executableTarget(
            name: "collector",
            dependencies: ["ClaudeUsageBarCore"]
        ),
        .testTarget(
            name: "ClaudeUsageBarCoreTests",
            dependencies: ["ClaudeUsageBarCore"]
        ),
        .testTarget(
            name: "ClaudeCodeUsageBarTests",
            dependencies: ["ClaudeCodeUsageBar", "ClaudeUsageBarCore"]
        ),
    ]
)
