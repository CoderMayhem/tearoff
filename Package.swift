// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tearoff",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tearoff", targets: ["Tearoff"]),
        .library(name: "TearoffCore", targets: ["TearoffCore"]),
    ],
    targets: [
        // Pads, day arithmetic and persistence. No AppKit, no SwiftUI — so it is testable.
        .target(name: "TearoffCore", path: "Sources/TearoffCore"),
        // The app: windows, views, menu bar.
        .executableTarget(name: "Tearoff", dependencies: ["TearoffCore"], path: "Sources/Tearoff"),
        .testTarget(name: "TearoffCoreTests", dependencies: ["TearoffCore"], path: "Tests/TearoffCoreTests"),
    ]
)
