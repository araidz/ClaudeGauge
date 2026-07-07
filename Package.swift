// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeGauge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClaudeGauge")
    ]
)
