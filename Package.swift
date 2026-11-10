// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "BackToBug",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "BackToBug", targets: ["BackToBug"])],
  targets: [
    .target(name: "ReplayCore"),
    .executableTarget(name: "BackToBug", dependencies: ["ReplayCore"]),
    .testTarget(name: "ReplayCoreTests", dependencies: ["ReplayCore"]),
  ]
)
