// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Peek",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "git@github.com:alexmx/swift-cli-mcp.git", branch: "main"),
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.3.0")
    ],
    targets: [
        .executableTarget(
            name: "peek",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftMCP", package: "swift-cli-mcp"),
                .product(name: "ToonFormat", package: "toon-swift")
            ],
            path: "Sources/Peek"
        ),
        .testTarget(
            name: "PeekTests",
            dependencies: ["peek"]
        )
    ]
)
