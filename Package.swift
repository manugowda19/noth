// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchFlow",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NotchFlow",
            path: "Sources/NotchFlow"
        )
    ]
)
