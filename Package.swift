// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TVRemoteApp",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TVRemoteApp",
            targets: ["TVRemoteApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/jareksedy/WebOSClient.git", from: "1.5.1")
    ],
    targets: [
        .executableTarget(
            name: "TVRemoteApp",
            dependencies: ["WebOSClient"],
            path: "."
        )
    ]
)
