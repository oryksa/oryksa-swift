// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Oryksa",
    // tvOS 15: the same floor as iOS 15 (async URLSession, AsyncImage, FocusState, .task), and every Apple TV
    // that runs App Store apps today can install it.
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15)],
    products: [
        .library(name: "Oryksa", targets: ["Oryksa"]),
        // The TV pieces (Apple TV): presenter, assistant panel for the remote, phone voice. A separate product,
        // so phone apps do not carry it.
        .library(name: "OryksaTV", targets: ["OryksaTV"]),
    ],
    targets: [
        .target(name: "Oryksa", path: "Sources/Oryksa"),
        .target(name: "OryksaTV", dependencies: ["Oryksa"], path: "Sources/OryksaTV"),
        .testTarget(name: "OryksaTests", dependencies: ["Oryksa"], path: "Tests/OryksaTests", resources: [.copy("voice")]),
        .testTarget(name: "OryksaTVTests", dependencies: ["OryksaTV", "Oryksa"], path: "Tests/OryksaTVTests"),
    ]
)
