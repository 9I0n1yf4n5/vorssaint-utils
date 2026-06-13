// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vorssaint",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Vorssaint",
            path: "Sources/Vorssaint"
        )
    ]
)
