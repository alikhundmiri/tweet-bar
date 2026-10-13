// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TweetBar",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "TweetBar",
            path: "Sources/TweetBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
