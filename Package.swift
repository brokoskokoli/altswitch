// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "AltSwitch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AltSwitch", targets: ["AltSwitch"])
    ],
    targets: [
        .executableTarget(
            name: "AltSwitch",
            path: "Sources/AltSwitch"
        )
    ]
)
