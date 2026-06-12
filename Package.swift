// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VorssaintUtils",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VorssaintUtils",
            path: "Sources/VorssaintUtils"
        )
    ]
)
