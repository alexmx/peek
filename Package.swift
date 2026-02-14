// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Peek",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(path: "../swift-cli-mcp"),
    ],
    targets: [
        .executableTarget(
            name: "peek",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftCliMcp", package: "swift-cli-mcp"),
            ],
            path: "Sources/Peek"
        )
    ]
)
