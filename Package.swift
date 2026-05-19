// swift-tools-version: 5.9
import PackageDescription

// Sentry ships two products from one tree: `SentryPane` (the whole
// feature as a dynamic library, exposed via SuiteKit so the
// MattsSoftware launcher can load it out of an installed Sentry.app)
// and `Sentry` (a thin @main shim that hosts that pane standalone —
// behaviour unchanged from before the split).
let package = Package(
    name: "Sentry",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sentry", targets: ["Sentry"]),
        .library(name: "SentryPane", type: .dynamic, targets: ["SentryPane"])
    ],
    dependencies: [ .package(path: "../suitekit-swift") ],
    targets: [
        .target(
            name: "SentryPane",
            dependencies: [.product(name: "SuiteKit", package: "suitekit-swift")],
            path: "Sources/SentryPane"
        ),
        .executableTarget(
            name: "Sentry",
            dependencies: ["SentryPane", .product(name: "SuiteKit", package: "suitekit-swift")],
            path: "Sources/Sentry"
        )
    ]
)
