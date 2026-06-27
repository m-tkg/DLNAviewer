// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DLNAKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "DLNAKit", targets: ["DLNAKit"]),
    ],
    targets: [
        .target(name: "DLNAKit"),
        .executableTarget(name: "ssdpprobe", dependencies: ["DLNAKit"]),
        .testTarget(
            name: "DLNAKitTests",
            dependencies: ["DLNAKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
