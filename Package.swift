// swift-tools-version: 6.2
// Untitled — on-device file naming. See docs/SPEC.md.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "Untitled",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "UntitledCore", targets: ["UntitledCore"]),
        .library(name: "UntitledFS", targets: ["UntitledFS"]),
        .library(name: "UntitledStore", targets: ["UntitledStore"]),
        .library(name: "UntitledModel", targets: ["UntitledModel"]),
        .library(name: "UntitledExtract", targets: ["UntitledExtract"]),
        .library(name: "UntitledEngine", targets: ["UntitledEngine"]),
        .library(name: "UntitledUI", targets: ["UntitledUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.9.0"),
    ],
    targets: [
        .target(name: "CUntitledSys"),
        .target(name: "CSQLiteSnapshotStubs"),
        .target(name: "UntitledCore", swiftSettings: swiftSettings),
        .target(name: "UntitledFS", dependencies: ["UntitledCore", "CUntitledSys"], swiftSettings: swiftSettings),
        .target(
            name: "UntitledStore",
            dependencies: [
                "UntitledCore", "UntitledFS", .product(name: "GRDB", package: "GRDB.swift"),
                .target(name: "CSQLiteSnapshotStubs", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: swiftSettings
        ),
        .target(name: "UntitledModel", dependencies: ["UntitledCore"], swiftSettings: swiftSettings),
        .target(name: "UntitledExtract", dependencies: ["UntitledCore"], swiftSettings: swiftSettings),
        .target(
            name: "UntitledEngine",
            dependencies: ["UntitledCore", "UntitledFS", "UntitledStore", "UntitledModel", "UntitledExtract"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "UntitledUI",
            dependencies: ["UntitledCore", "UntitledFS", "UntitledStore", "UntitledModel", "UntitledExtract", "UntitledEngine"],
            swiftSettings: swiftSettings
        ),
        // Test-only helper process for the kill -9 journal test (J3). Not part of the app.
        .executableTarget(
            name: "untitled-journal-harness",
            dependencies: ["UntitledCore", "UntitledFS", "UntitledStore"],
            path: "Tools/JournalHarness",
            swiftSettings: swiftSettings
        ),
        .target(name: "UntitledTestSupport", path: "Tests/UntitledTestSupport", swiftSettings: swiftSettings),
        .testTarget(name: "UntitledCoreTests", dependencies: ["UntitledCore", "UntitledTestSupport"], swiftSettings: swiftSettings),
        .testTarget(name: "UntitledFSTests", dependencies: ["UntitledFS", "UntitledCore", "UntitledStore", "UntitledTestSupport", "untitled-journal-harness"], swiftSettings: swiftSettings),
        .testTarget(name: "UntitledStoreTests", dependencies: ["UntitledStore", "UntitledCore", "UntitledFS", "UntitledTestSupport"], swiftSettings: swiftSettings),
        .testTarget(name: "UntitledModelTests", dependencies: ["UntitledModel", "UntitledCore", "UntitledTestSupport"], swiftSettings: swiftSettings),
        .testTarget(name: "UntitledExtractTests", dependencies: ["UntitledExtract", "UntitledCore"], resources: [.copy("Fixtures")], swiftSettings: swiftSettings),
        .testTarget(
            name: "UntitledEngineTests",
            dependencies: ["UntitledEngine", "UntitledCore", "UntitledFS", "UntitledStore", "UntitledModel", "UntitledExtract", "UntitledTestSupport"],
            swiftSettings: swiftSettings
        ),
    ]
)
