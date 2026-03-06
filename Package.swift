// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let approachableConcurrencySettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "OSXQuery",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "OSXQuery", targets: ["OSXQuery"]),
        .executable(name: "osq", targets: ["osq"]),
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/Commander.git", exact: "0.2.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
    ],
    targets: [
        .target(
            name: "OSXQuery",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/OSXQuery",
            exclude: [],
            sources: nil,
            swiftSettings: approachableConcurrencySettings
        ),
        .executableTarget(
            name: "osq",
            dependencies: [
                "OSXQuery",
                .product(name: "Commander", package: "Commander"),
            ],
            path: "Sources/osq",
            swiftSettings: approachableConcurrencySettings
        ),
        .testTarget(
            name: "OSXQueryTests",
            dependencies: [
                "OSXQuery",
            ],
            path: "Tests/OSXQueryTests",
            swiftSettings: approachableConcurrencySettings
        ),
        .testTarget(
            name: "osqTests",
            dependencies: [
                "osq",
                "OSXQuery",
            ],
            path: "Tests/osqTests",
            swiftSettings: approachableConcurrencySettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
