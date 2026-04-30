// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentBar",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.54.0"),
        .package(url: "https://github.com/realm/SwiftLint", from: "0.57.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentBar",
            path: "Sources/AgentBar",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint"),
            ]
        ),
    ]
)
