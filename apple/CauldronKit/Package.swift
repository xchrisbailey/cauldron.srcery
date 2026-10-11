// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CauldronKit",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [
    .library(name: "CauldronKit", targets: ["CauldronKit"])
  ],
  targets: [
    .target(name: "CauldronKit"),
    .testTarget(name: "CauldronKitTests", dependencies: ["CauldronKit"]),
  ],
  swiftLanguageModes: [.v6]
)
