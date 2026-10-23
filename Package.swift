// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "slip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "slip",
            path: "Sources/slip"
        )
    ]
)
