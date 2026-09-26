# Legacy

The first CookAlong version played a local video with AVPlayer and transcribed it on device.
On 2026-09-26 the app was rebuilt around a YouTube link + pasted transcript and a slideshow.

Nothing in this folder is compiled: it sits outside every synchronized folder of the Xcode
project. It is kept because parts are worth mining when the real services land:

- `Services/` — transcript -> recipe pipeline for the on-device model (chunking, step merging,
  timestamp clamping, cloud fallback) and its tests in `CookAlongTests/` (run via `Package.swift`
  from here after fixing the paths). Written against the old `Models/Recipe.swift` (`videoStart`
  instead of `startSecond`, no `sourceURL`/`thumbnailURL`/`channel`).
- `Services/Images/` — AI step images from an OpenAI-style endpoint, caching, a loader that
  prioritises the current step. The video-frame sampler only makes sense with a local video.
- `Session/Voice/` — AVSpeechSynthesizer read-aloud, spoken-command matching, timer notifications,
  audio session handling. The microphone listener (`VoiceController`) was mid-move when the
  session stopped and is not here.
- `Views/` — the old guide/hands-free panels.

Delete this folder whenever it stops being useful.
