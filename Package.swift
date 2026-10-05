// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "EZnote",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "EZnote",
            path: "Sources/EZnote"
        )
    ],
    swiftLanguageModes: [.v5]
)
