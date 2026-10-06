// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RedactionRules",
    platforms: [
        // macOS is listed so `swift test` runs on a developer's machine
        // without a simulator. Nothing here is iOS-only: the rules are
        // patterns, checksums and Foundation.
        .iOS("26.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "RedactionRules", targets: ["RedactionRules"]),
        // Synthetic page layouts for tests and audit tools; not for the app.
        .library(name: "RedactionRulesTestSupport", targets: ["RedactionRulesTestSupport"]),
    ],
    targets: [
        .target(
            name: "RedactionRules",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "RedactionRulesTestSupport",
            dependencies: ["RedactionRules"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RedactionRulesTests",
            dependencies: ["RedactionRules", "RedactionRulesTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
