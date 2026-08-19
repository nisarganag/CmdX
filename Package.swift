// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmdX",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CmdXCore"),
        .executableTarget(name: "CmdXCoreTests", dependencies: ["CmdXCore"]),
        .executableTarget(name: "CmdXApp", dependencies: ["CmdXCore"]),
    ]
)
