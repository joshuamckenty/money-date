// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoneyDate",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MoneyDate",
            path: "Sources/MoneyDate"
        )
    ]
)
