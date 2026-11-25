// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProjectHub",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ProjectHub", targets: ["ProjectHub"])],
    targets: [
        .executableTarget(name: "ProjectHub"),
        .testTarget(name: "ProjectHubTests", dependencies: ["ProjectHub"])
    ]
)
