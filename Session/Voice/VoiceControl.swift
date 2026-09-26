import Foundation
import Observation

// Owned by session 4 (Session/Voice/). CookSession only knows these protocols.

/// What a cook can say while a recipe is open. See `CommandMatcher` for the spoken forms.
nonisolated enum VoiceCommand: Equatable, Sendable {
    case next, back, repeatStep, startTimer, stopTimer
    /// Move the video by this many seconds (negative moves back). "Skip ahead ten seconds".
    case skip(seconds: Int)
    case pauseVideo, playVideo
    /// "Go to step three": one-based, as spoken.
    case goToStep(Int)
    /// The ingredients slide.
    case ingredients
    /// Say what the current step needs.
    case whatDoINeed
    /// Say how long the timer (or the step) has left.
    case timeLeft

    /// Short form for the UI ("Heard: start timer").
    var label: String {
        switch self {
        case .next:       "next"
        case .back:       "back"
        case .repeatStep: "repeat"
        case .startTimer: "start timer"
        case .stopTimer:  "stop timer"
        case .skip(let seconds):
            seconds >= 0 ? "skip ahead \(seconds) s" : "skip back \(-seconds) s"
        case .pauseVideo: "pause"
        case .playVideo:  "play"
        case .goToStep(let n): "step \(n)"
        case .ingredients: "ingredients"
        case .whatDoINeed: "what do I need"
        case .timeLeft:    "time left"
        }
    }

    /// One example of each command, for help text and the recognizer's vocabulary.
    static let examples: [VoiceCommand] = [.next, .back, .repeatStep, .startTimer, .stopTimer, .skip(seconds: 10),
                                            .skip(seconds: -10), .pauseVideo, .playVideo, .goToStep(3), .ingredients,
                                            .whatDoINeed, .timeLeft]
}

nonisolated enum VoiceStatus: Equatable, Sendable {
    case off, starting, listening, denied, unavailable
    case failed(String)

    var isListening: Bool { self == .listening }

    /// One line for the status bar under the slideshow.
    var label: String {
        switch self {
        case .off:         "Mic off"
        case .starting:    "Starting the mic…"
        case .listening:   "Listening"
        case .denied:      "Allow the microphone and speech recognition in Settings"
        case .unavailable: "Voice control isn't available right now"
        case .failed(let message): message
        }
    }
}

/// Hears the cook's commands and reports them on the main actor.
/// `Observable` so views can show `status` and `heard` directly.
@MainActor
protocol VoiceControl: AnyObject, Observable {
    var status: VoiceStatus { get }
    /// Tail of what is currently being heard, "" when nothing; shown so the cook can see it's working.
    var heard: String { get }
    /// Called on the main actor once per recognized command.
    var onCommand: ((VoiceCommand) -> Void)? { get set }

    func startListening() async
    func stopListening()
}

/// Reads text aloud.
@MainActor
protocol Speaker: AnyObject, Observable {
    var isSpeaking: Bool { get }
    /// Replaces whatever is currently being said.
    func speak(_ text: String)
    func stopSpeaking()
}

// MARK: - Stubs so the app runs end to end before session 4 lands

/// Never hears anything. Reports `.unavailable` while "on" so the status bar says why.
@Observable
final class SilentVoiceControl: VoiceControl {
    private(set) var status: VoiceStatus = .off
    private(set) var heard = ""
    var onCommand: ((VoiceCommand) -> Void)?

    func startListening() async { status = .unavailable }
    func stopListening() { status = .off }
}

/// Says nothing.
@Observable
final class SilentSpeaker: Speaker {
    private(set) var isSpeaking = false
    func speak(_ text: String) {}
    func stopSpeaking() {}
}
