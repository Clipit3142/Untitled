// swift-tools-version: 6.2
// Nomen — on-device file naming. See docs/SPEC.md.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "Nomen",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "NomenCore", targets: ["NomenCore"]),
        .library(name: "NomenFS", targets: ["NomenFS"]),
        .library(name: "NomenStore", targets: ["NomenStore"]),
        .library(name: "NomenModel", targets: ["NomenModel"]),
        .library(name: "NomenExtract", targets: ["NomenExtract"]),
        .library(name: "NomenEngine", targets: ["NomenEngine"]),
        .library(name: "NomenUI", targets: ["NomenUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.9.0"),
    ],
    targets: [
        .target(name: "CNomenSys"),
        .target(name: "CSQLiteSnapshotStubs"),
        .target(name: "NomenCore", swiftSettings: swiftSettings),
        .target(name: "NomenFS", dependencies: ["NomenCore", "CNomenSys"], swiftSettings: swiftSettings),
        .target(
            name: "NomenStore",
            dependencies: [
                "NomenCore", "NomenFS", .product(name: "GRDB", package: "GRDB.swift"),
                .target(name: "CSQLiteSnapshotStubs", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: swiftSettings
        ),
        .target(name: "NomenModel", dependencies: ["NomenCore"], swiftSettings: swiftSettings),
        .target(name: "NomenExtract", dependencies: ["NomenCore"], swiftSettings: swiftSettings),
        .target(
            name: "NomenEngine",
            dependencies: ["NomenCore", "NomenFS", "NomenStore", "NomenModel", "NomenExtract"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "NomenUI",
            dependencies: ["NomenCore", "NomenFS", "NomenStore", "NomenModel", "NomenExtract", "NomenEngine"],
            swiftSettings: swiftSettings
        ),
        // Test-only helper process for the kill -9 journal test (J3). Not part of the app.
        .executableTarget(
            name: "nomen-journal-harness",
            dependencies: ["NomenCore", "NomenFS", "NomenStore"],
            path: "Tools/JournalHarness",
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "NomenCoreTests", dependencies: ["NomenCore"], swiftSettings: swiftSettings),
        .testTarget(name: "NomenFSTests", dependencies: ["NomenFS", "NomenCore", "NomenStore"], swiftSettings: swiftSettings),
        .testTarget(name: "NomenStoreTests", dependencies: ["NomenStore", "NomenCore", "NomenFS"], swiftSettings: swiftSettings),
        .testTarget(name: "NomenModelTests", dependencies: ["NomenModel", "NomenCore"], swiftSettings: swiftSettings),
        .testTarget(name: "NomenExtractTests", dependencies: ["NomenExtract", "NomenCore"], resources: [.copy("Fixtures")], swiftSettings: swiftSettings),
        .testTarget(
            name: "NomenEngineTests",
            dependencies: ["NomenEngine", "NomenCore", "NomenFS", "NomenStore", "NomenModel", "NomenExtract"],
            swiftSettings: swiftSettings
        ),
    ]
)
