# CookAlong — Bitrig Hacks

Paste a YouTube cooking video, get a slideshow you can cook along to: an ingredients
checklist, one slide per step with a picture and real kitchen times, a timer, read-aloud,
and voice commands. Built for the iOS 27 SDK and the iPhone Duo.

```
YouTube link (+ pasted transcript) ──► RecipeSource ──► Recipe { steps[…] }
                                                            │
                          StepImageProvider ◄───────────────┤──────────► slides
                          VoiceControl / Speaker ◄──────────┘   (CookSession drives both panels)
```

## Layout

`Views/RootView.swift` sizes everything from its container, never `UIScreen`.
Tall containers (closed, or open and rotated) stack the details panel over the slideshow;
wide ones (open) put them side by side. Both split 50/50 on the physical centre line so
the hinge falls between the panels.

## Who owns what

| Folder | Owner | Plug-in point |
|---|---|---|
| `Services/Recipe/` | session 2 | `RecipeSource` |
| `Services/Images/` | session 3 | `StepImageProvider` |
| `Session/Voice/` | session 4 | `VoiceControl`, `Speaker` |
| everything else (`App/`, `Models/`, `Session/CookSession.swift`, `Views/`, project) | session 1 | |

Swap your implementation into `CookSession.live()` (one line each). The stubs there keep the app
running end to end: the Demo button never needs a model, mic or network.

## The contracts

```swift
// Services/Recipe/RecipeSource.swift
@MainActor protocol RecipeSource {
    func recipe(youtubeURL: URL, transcript: String?) async throws -> Recipe
}
// Throw RecipeSourceError (.notAYouTubeLink, .transcriptUnavailable, .modelUnavailable,
// .couldNotUnderstand(String)) for messages the form can show; any Error is displayed via localizedDescription.

// Services/Images/StepImageProvider.swift
@MainActor protocol StepImageProvider {
    func image(for step: RecipeStep, in recipe: Recipe) async -> UIImage?   // nil = keep the placeholder
}

// Session/Voice/VoiceControl.swift
nonisolated enum VoiceCommand: String, CaseIterable, Sendable { case next, back, repeatStep, startTimer, stopTimer }
nonisolated enum VoiceStatus: Equatable, Sendable { case off, starting, listening, denied, unavailable, failed(String) }

@MainActor protocol VoiceControl: AnyObject, Observable {
    var status: VoiceStatus { get }
    var heard: String { get }                              // tail of what's being heard, "" if nothing
    var onCommand: ((VoiceCommand) -> Void)? { get set }   // called on the main actor, once per command
    func startListening() async
    func stopListening()
}

@MainActor protocol Speaker: AnyObject, Observable {
    var isSpeaking: Bool { get }
    func speak(_ text: String)                             // replaces whatever is being said
    func stopSpeaking()
}
```

All protocols are called on the main actor; do heavy work off it and hop back. `Recipe`,
`RecipeStep`, `VoiceCommand`, `VoiceStatus` and `CountdownTimer` are `nonisolated` value types,
so they can be built anywhere. Models are in `Models/Recipe.swift`; `YouTubeLink` parses IDs and
builds watch/thumbnail URLs.

## Build and run

```
xcodebuild -scheme CookAlong -destination 'platform=iOS Simulator,name=iPhone Duo' build
```

Settings: Swift 5 language mode on the Swift 6.4 compiler, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
approachable concurrency, MemberImportVisibility, deployment target iOS 26. Zero-warning policy.
Debug builds take launch arguments for screenshots: see `App/DebugLaunchOptions.swift`.

`Info.plist` already has the microphone and speech-recognition usage strings. Optional API keys
go in there too (commented examples inside); never ship one.

`Legacy/` holds the first, local-video version (AVPlayer, on-device transcription, the old
recipe pipeline and its tests). It is not compiled; mine it or delete it.
