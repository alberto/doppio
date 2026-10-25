// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Doppio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Doppio", path: "Sources/Doppio")
    ]
)
