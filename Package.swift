// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sentry",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sentry",
            path: "Sources/Sentry"
        )
    ]
)
