// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StellarRep",
    platforms: [
        .iOS(.v16),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "StellarRep",
            targets: ["StellarRep"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Soneso/stellar-ios-mac-sdk.git", from: "3.10.0"),
    ],
    targets: [
        .target(
            name: "StellarRep",
            dependencies: [
                .product(name: "stellarsdk", package: "stellar-ios-mac-sdk"),
            ]),
        .testTarget(
            name: "StellarRepTests",
            dependencies: ["StellarRep"]
        ),
    ]
)
