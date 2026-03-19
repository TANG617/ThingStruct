// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ThingStructCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ThingStructCore",
            targets: ["ThingStructCore"]
        )
    ],
    targets: [
        .target(
            name: "ThingStructCore",
            path: "ThingStruct/CoreShared"
        ),
        .testTarget(
            name: "ThingStructCoreTests",
            dependencies: ["ThingStructCore"],
            path: "Tests/ThingStructCoreTests"
        )
    ]
)
