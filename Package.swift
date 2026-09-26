// swift-tools-version: 6.2
//
// Test harness only. The app is built from CookAlong.xcodeproj (synchronized folders App/,
// Models/, Services/, Session/, Views/, Resources/); this manifest sits outside all of them and
// is not part of that build. It compiles the YouTube-link -> Recipe service with the same
// language settings as the Xcode target and runs the Swift Testing suite in CookAlongTests/
// natively on a Mac (macOS 26+, where FoundationModels exists):
//
//     swift test
//
// Only Models/ and Services/Recipe/ are compiled here; the UIKit-facing folders are left out.
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
            exclude: ["App", "Views", "Session", "Resources", "Legacy", "CookAlong.xcodeproj", "CookAlongTests",
                      "Info.plist", "README.md", "Package.swift"],
            sources: ["Models", "Services/Recipe", "Services/Images/KitchenAssets.swift"],
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
