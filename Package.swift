// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpottrCore",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "SpottrCore", targets: ["SpottrCore"])],
    targets: [
        .target(name: "SpottrCore", path: "Shared/Core"),
        .testTarget(name: "SpottrCoreTests", dependencies: ["SpottrCore"], path: "Tests/Core")
    ],
    swiftLanguageModes: [.v5]
)
