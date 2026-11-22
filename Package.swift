// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clothesline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Clothesline")
    ]
)
