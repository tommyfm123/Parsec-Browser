// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Parsec",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Parsec",
            path: "Sources/Parsec",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
