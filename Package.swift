// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacCleaner",
            path: "Sources/MacCleaner"
        )
    ]
)
