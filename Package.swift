// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FrigateNVR",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "FrigateNVR",
            targets: ["FrigateNVR"]
        ),
    ],
    dependencies: [
        // MQTT client for real-time event notifications
        .package(url: "https://github.com/emqx/CocoaMQTT.git", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "FrigateNVR",
            dependencies: [
                .product(name: "CocoaMQTT", package: "CocoaMQTT"),
            ],
            path: "FrigateNVR"
        ),
        .testTarget(
            name: "FrigateNVRTests",
            dependencies: ["FrigateNVR"],
            path: "FrigateNVRTests"
        ),
    ]
)
