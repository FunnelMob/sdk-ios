// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FunnelMob",
    platforms: [
        .iOS(.v14),
        .macOS(.v12),
        .tvOS(.v14),
        .watchOS(.v7)
    ],
    products: [
        .library(
            name: "FunnelMob",
            targets: ["FunnelMob"]
        ),
    ],
    targets: [
        .target(
            name: "FunnelMob",
            dependencies: [],
            path: "Sources/FunnelMob"
        ),
        .testTarget(
            name: "FunnelMobTests",
            dependencies: ["FunnelMob"],
            path: "Tests/FunnelMobTests"
        ),
    ]
)
