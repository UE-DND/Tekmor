// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Tekmor",
  defaultLocalization: "en",
  platforms: [.macOS(.v15)],
  products: [.library(name: "TekmorCore", targets: ["TekmorCore"])],
  targets: [
    .target(
      name: "TekmorCore",
      resources: [.process("Resources")]
    ),
    .testTarget(name: "TekmorCoreTests", dependencies: ["TekmorCore"]),
  ],
  swiftLanguageModes: [.v6]
)
