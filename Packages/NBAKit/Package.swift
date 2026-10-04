// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NBAKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(name: "NBAKit", targets: ["NBAKit"]),
    ],
    targets: [
        .target(
            name: "NBAKit",
            resources: [
                .copy("Resources/teams.json"),
            ]
        ),
        .testTarget(
            name: "NBAKitTests",
            dependencies: ["NBAKit"]
        ),
    ]
)
