// swift-tools-version: 5.9
//
// Lightweight SwiftPM package for unit-testing pure functions extracted from
// the Xcode app target. The .xcodeproj remains the authoritative app build;
// this manifest exists only so contributors can run:
//
//     swift test
//
// against pure-function helpers without spinning up Xcode. Targets reference
// existing source files in place via `path:` + `sources:` — no duplication,
// no drift. As more pure code is extracted into focused files, add it to the
// VibeCockpitCore target's `sources` and write tests in Tests/.
//
import PackageDescription

let package = Package(
    name: "VibeCockpitTests",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VibeCockpitCore", targets: ["VibeCockpitCore"]),
        .executable(name: "VibeCockpitCoreChecks", targets: ["VibeCockpitCoreChecks"])
    ],
    targets: [
        .target(
            name: "VibeCockpitCore",
            path: "VibeCockpit/Models",
            exclude: [
                "Account.swift",
                "CodexExtraUsageData+Formatting.swift",
                "DiagnosticReport.swift",
                "ProviderType.swift",
                "UserSettings.swift"
            ],
            sources: [
                "ClaudeAPIResponseModels.swift",
                "CodexUsageData.swift",
                "CodexWakeupCore.swift",
                "UsageDisplayMath.swift"
            ]
        ),
        .executableTarget(
            name: "VibeCockpitCoreChecks",
            dependencies: ["VibeCockpitCore"],
            path: "Checks/VibeCockpitCoreChecks"
        ),
        .testTarget(
            name: "VibeCockpitCoreTests",
            dependencies: ["VibeCockpitCore"],
            path: "Tests/VibeCockpitCoreTests"
        )
    ]
)
