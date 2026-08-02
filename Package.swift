// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AwaySwitch",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "AwaySwitchCore", targets: ["AwaySwitchCore"]),
        .executable(name: "AwaySwitch", targets: ["AwaySwitch"]),
    ],
    targets: [
        .target(name: "AwaySwitchCore"),
        .executableTarget(
            name: "AwaySwitch",
            dependencies: ["AwaySwitchCore"]
        ),
        .testTarget(
            name: "AwaySwitchCoreTests",
            dependencies: ["AwaySwitchCore"]
        ),
    ]
)
