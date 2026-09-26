import Foundation
import Observation

// Owned by session 4 (Session/Voice/). CookSession only knows these protocols.

/// What a cook can say while a recipe is open.
nonisolated enum VoiceCommand: String, CaseIterable, Sendable {
    case next, back, repeatStep, startTimer, stopTimer

    /// Short form for the UI ("Heard: start timer").
    var label: String {
        switch self {
        case .next:       "next"
        case .back:       "back"
        case .repeatStep: "repeat"
        case .startTimer: "start timer"
        case .stopTimer:  "stop timer"
        }
    }
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
