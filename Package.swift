// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingyueCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "LingyueCore", targets: ["LingyueCore"])],
    targets: [
        .target(name: "LingyueCore", path: "Core"),
        .testTarget(name: "LingyueCoreTests", dependencies: ["LingyueCore"], path: "tests")
    ]
)
