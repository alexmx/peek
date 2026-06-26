// swift-tools-version: 6.2

import PackageDescription

/// Swift 6.2 approachable concurrency (SE-461 + SE-470); nonisolated-by-default retained.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances")
]

let package = Package(
    name: "Peek",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/alexmx/swift-cli-mcp.git", from: "1.1.0"),
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
            path: "Sources/Peek",
            swiftSettings: approachableConcurrency
        ),
        .testTarget(
            name: "PeekTests",
            dependencies: ["peek"],
            swiftSettings: approachableConcurrency
        )
    ]
)
