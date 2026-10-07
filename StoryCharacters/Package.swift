// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StoryCharacters",
    defaultLocalization: "ru",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(name: "StoryCharacters", targets: ["StoryCharacters"])
    ],
    targets: [
        .target(
            name: "StoryCharacters",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "StoryCharactersTests",
            dependencies: ["StoryCharacters"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
