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
    targets: [
        .executableTarget(
            name: "TVRemoteApp",
            path: "."
        )
    ]
)
