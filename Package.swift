// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Oryksa",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "Oryksa", targets: ["Oryksa"]),
    ],
    targets: [
        .target(name: "Oryksa", path: "Sources/Oryksa"),
        .testTarget(name: "OryksaTests", dependencies: ["Oryksa"], path: "Tests/OryksaTests", resources: [.copy("voice")]),
    ]
)
