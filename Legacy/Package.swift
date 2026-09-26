// swift-tools-version: 6.2
//
// Test harness only. The app is built from CookAlong.xcodeproj (synchronized folders App/, Models/,
// Services/, Session/, Views/, Resources/); this manifest is not part of that build. It compiles
// the transcript -> recipe pipeline with the same language settings as the Xcode target and runs
// the Swift Testing suite in CookAlongTests/ on a Mac:
//
//     swift test
//
// UIKit-only files (Views/, Session/, Services/Images/, StepImageProvider.swift) are left out so
// the harness runs natively on macOS 26+, where FoundationModels, Speech and AVFoundation all exist.
import PackageDescription

let appSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("MemberImportVisibility"),
    // What SWIFT_APPROACHABLE_CONCURRENCY = YES turns on in Xcode.
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .unsafeFlags(["-warnings-as-errors"]),
]

let package = Package(
    name: "CookAlong",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    targets: [
        .target(
            name: "CookAlong",
            path: ".",
            exclude: ["App", "Views", "Session", "Resources", "Services/Images", "Services/StepImageProvider.swift",
                      "CookAlong.xcodeproj", "CookAlongTests", "Info.plist", "README.md", "Package.swift"],
            sources: ["Models", "Services"],
            swiftSettings: appSettings
        ),
        .testTarget(
            name: "CookAlongTests",
            dependencies: ["CookAlong"],
            path: "CookAlongTests",
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("MemberImportVisibility")]
        ),
    ]
)
