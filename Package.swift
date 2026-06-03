// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPingMenu",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AgentPingMenu",
            path: "Sources/AgentPingMenu"
        )
    ]
)
