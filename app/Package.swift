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
        // Separate from the StellarRep library on purpose: this is the only
        // place `@main` lives, so it can't get linked into StellarRepTests
        // (which depends on StellarRep, not on this) — see StellarRepApp.swift.
        .library(
            name: "StellarRepApp",
            targets: ["StellarRepApp"]),
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
        .target(
            name: "StellarRepApp",
            dependencies: ["StellarRep"]),
        .testTarget(
            name: "StellarRepTests",
            dependencies: ["StellarRep"]
        ),
    ]
)
