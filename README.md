# CookAlong — Bitrig Hacks

Paste a YouTube cooking video to get a recipe with an ingredient checklist, illustrated
steps, a video panel that follows the current step, kitchen timers, optional read-aloud, and voice
commands. Captions can be fetched automatically; a pasted transcript is optional.
Built for the iOS 27 SDK and the iPhone Duo.

```
YouTube link (+ optional transcript) ──► RecipeSource ──► Recipe { steps[…] }
                                                               │
                              CookSession ◄────────────────────┘
                                  ├──► kitchen scenes + video + step needs
                                  └──► timer + voice + narration
```

## Layout

`Views/RootView.swift` sizes everything from its container, never `UIScreen`.
On the Duo's closed display, one scrollable cooking panel uses the full screen and keeps
slide and voice controls above the home indicator. Read-aloud remains an opt-in there,
since the video's audio plays only while its sheet is open; on the inner display the
video is visible and supplies the audio. A native menu jumps to any
step, and the video opens in a sheet. On the inner display, the video and details share
one side of the physical centre line, while the illustrated slideshow occupies the other.
The panels sit side by side when wide and stack when rotated. The layout breakpoint is
the shorter container dimension reaching 600 points; it should be revisited if a
posture-specific layout API is adopted.

The app follows the system's Light/Dark Mode, safe areas, controls and SF Pro Dynamic Type.
System background and secondary background colors form the surfaces. The light accent is
deep basil `#26633D`, the dark accent is mint `#8FD19E`; prominent fills stay dark green
for white-label contrast. Amber is reserved for the active timer. There is no app-specific
appearance setting.

## Components

| Folder | Responsibility |
|---|---|
| `Services/Recipe/` | YouTube metadata, captions, recipe extraction and per-step needs |
| `Services/Images/` | Bundled kitchen art, optional cached scene art and remote step images |
| `Session/Voice/` | Voice commands, narration and timer notifications |
| `Session/CookSession.swift` | Recipe, slide, checklist, timer and voice state |
| `Views/` | Adaptive cooking UI, video and step scenes |

The Demo button needs no recipe model or network. Live YouTube extraction depends on
captions and either Apple Intelligence on the device or a configured model key.

## The contracts

```swift
// Services/Recipe/RecipeSource.swift
@MainActor protocol RecipeSource {
    func recipe(for request: RecipeRequest) async throws -> SourcedRecipe
}

// Services/Images/StepImageProvider.swift
@MainActor protocol StepImageProvider {
    func image(for step: RecipeStep, in recipe: Recipe) async -> UIImage?   // optional remote image
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

## Build and run in Bitrig

On the Mac, check out `design/duo-kitchen-ui`, then choose **File → Open Folder…** in
Bitrig and select this repository folder. Bitrig detects the `CookAlong` Xcode project
and builds it for its built-in simulator. Use the **Fold** controls to try closed and
open poses, and rotate the simulator to check the landscape layout. For a separate
Xcode Simulator run, choose **Run on… → iPhone Duo → Play** from Bitrig's toolbar.
The **Demo** button is the quickest in-app check and needs no keys. **File → Add GitHub
Repository…** can also import the pushed branch.

To try a real YouTube link, copy `Config/Secrets.xcconfig.example` to the ignored
`Config/Secrets.xcconfig` and enter your own keys. The usual path is `OPENAI_API_KEY` for
recipe extraction and optionally `SUPADATA_API_KEY` for captions. The app can also use
YouTube captions and on-device Apple Intelligence where available, or a Gemini video key.
Never commit `Secrets.xcconfig`; the build places these values in the app bundle, so use
development keys only.

The equivalent command-line build is:

```
xcodebuild -scheme CookAlong -destination 'platform=iOS Simulator,name=iPhone Duo' build
```

Settings: Swift 5 language mode on the Swift 6.4 compiler, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
approachable concurrency, MemberImportVisibility, deployment target iOS 26. Zero-warning policy.
Debug builds take launch arguments for screenshots: see `App/DebugLaunchOptions.swift`.

`Info.plist` has the microphone and speech-recognition usage strings. Keys flow from the
ignored xcconfig during the build.

`Legacy/` holds the first, local-video version (AVPlayer, on-device transcription, the old
recipe pipeline and its tests). It is not compiled; mine it or delete it.
