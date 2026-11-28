// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Tekmor",
  defaultLocalization: "en",
  platforms: [.macOS(.v15)],
  products: [.library(name: "TekmorCore", targets: ["TekmorCore", "TekmorWorkbench"])],
  targets: [
    .target(
      name: "TekmorCore",
      dependencies: ["TekmorWorkbench"],
      resources: [.process("Resources")]
    ),
    .target(name: "TekmorWorkbench"),
    .testTarget(name: "TekmorWorkbenchTests", dependencies: ["TekmorWorkbench"]),
    .testTarget(name: "TekmorCoreTests", dependencies: ["TekmorCore"]),
  ],
  swiftLanguageModes: [.v6]
)
