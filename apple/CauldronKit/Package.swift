// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CauldronKit",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [
    .library(name: "CauldronKit", targets: ["CauldronKit"])
  ],
  dependencies: [
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.14.2")
  ],
  targets: [
    .target(
      name: "CauldronKit",
      dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")]),
    .testTarget(
      name: "CauldronKitTests", dependencies: ["CauldronKit"],
      resources: [.copy("Imports/Fixtures")]),
  ],
  swiftLanguageModes: [.v6]
)
