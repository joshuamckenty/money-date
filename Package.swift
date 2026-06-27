// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoneyDate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/10in30/dopamine.git", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "MoneyDate",
            dependencies: [
                .product(name: "DopamineCore", package: "dopamine"),
                .product(name: "DopamineEffectConfetti", package: "dopamine"),
                .product(name: "DopamineEffectRipple", package: "dopamine"),
            ],
            path: "Sources/MoneyDate"
        )
    ]
)
