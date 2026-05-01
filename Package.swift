// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacCleaner",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MacCleaner"
        ),
        .testTarget(
            name: "MacCleanerTests",
            dependencies: ["MacCleaner"],
            path: "Tests/MacCleanerTests"
        ),
    ]
)
