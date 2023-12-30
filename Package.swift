// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "engine.io-vapor",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "EngineIO", targets: ["EngineIO"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "EngineIO",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
    ]
)
