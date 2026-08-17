// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeTokenCounter",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "CCUsageCore"),
        .executableTarget(name: "ClaudeTokenCounter", dependencies: ["CCUsageCore"]),
        .testTarget(name: "CCUsageCoreTests", dependencies: ["CCUsageCore"]),
    ]
)
