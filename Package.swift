// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrueRate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TrueRate",
            path: "Sources/TrueRate"
        )
    ]
)
