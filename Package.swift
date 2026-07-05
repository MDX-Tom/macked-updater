// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "macked-updater",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "macked-updater", targets: ["MackedUpdater"])
    ],
    targets: [
        .executableTarget(
            name: "MackedUpdater",
            path: ".",
            exclude: [
                "README.md",
                "README.zh-CN.md",
                "assets",
                "dist",
                "tools",
                "deploy"
            ],
            sources: [
                "App",
                "Models",
                "Services",
                "Persistence",
                "Views"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MackedUpdaterTests",
            dependencies: ["MackedUpdater"],
            path: "Tests/MackedUpdaterTests"
        )
    ]
)
