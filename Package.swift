// swift-tools-version: 5.9
// Package.swift — Alternative to Xcode project for CI / non-Mac environments
// On Mac, use LifeOptimizer.xcodeproj instead for ARKit support

import PackageDescription

let package = Package(
    name: "LifeOptimizer",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "LifeOptimizer", targets: ["LifeOptimizer"])
    ],
    targets: [
        .target(
            name: "LifeOptimizer",
            path: "LifeOptimizer",
            exclude: ["App"],  // App entry point requires @main, not suitable for library
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LifeOptimizerTests",
            dependencies: ["LifeOptimizer"],
            path: "LifeOptimizerTests"
        )
    ]
)
