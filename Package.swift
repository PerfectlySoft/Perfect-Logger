// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerfectLogger",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "PerfectLogger", targets: ["PerfectLogger"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "PerfectLogger",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectLoggerTests",
            dependencies: ["PerfectLogger"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
