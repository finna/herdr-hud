// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HerdrHUD", platforms: [.macOS(.v13)], products: [.executable(name: "HerdrHUD", targets: ["HerdrHUD"])], targets: [
    .executableTarget(name: "HerdrHUD", resources: [.copy("Resources")]),
    .testTarget(name: "HerdrHUDTests", dependencies: ["HerdrHUD"])
])
