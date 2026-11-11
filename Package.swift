// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Crocini",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Crocini",
            path: "Sources/Crocini"
        )
    ]
)
