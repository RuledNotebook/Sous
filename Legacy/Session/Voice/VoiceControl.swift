import Foundation
import Observation

// The contracts CookSession talks to. Implementations live next to this file;
// CookSession.live() picks them in one line.

/// What a cook can say while a recipe is open.
enum VoiceCommand: String, CaseIterable, Sendable {
    case next, back, repeatStep, pause, play, startTimer, stopTimer

    /// Short form for the UI ("Heard: start timer").
    var label: String {
        switch self {
        case .next: "next"
        case .back: "back"
        case .repeatStep: "repeat"
        case .pause: "pause"
        case .play: "play"
        case .startTimer: "start timer"
        case .stopTimer: "stop timer"
        }
    }
}

/// Which permission is missing when voice control can't listen.
enum VoicePermission: Equatable, Sendable {
    case microphone, speechRecognition
}

enum VoiceControlState: Equatable, Sendable {
    case off, starting, listening
    case denied(VoicePermission)
    case unavailable
    case failed(String)

    var isListening: Bool { self == .listening }
}

/// Hears commands on the microphone and reports them on the main actor.
@MainActor
protocol VoiceControl: AnyObject, Observable {
    var state: VoiceControlState { get }
    /// Tail of what is currently being heard, so the cook can see it's working.
    var heard: String { get }
    var lastCommand: VoiceCommand? { get }
    var lastCommandAt: Date? { get }
    /// Called on the main actor once per new command.
    var onCommand: ((VoiceCommand) -> Void)? { get set }
    /// While true nothing heard is acted on (the app itself is talking).
    var muted: Bool { get set }

    func start() async
    func stop()
}

/// Reads a step out loud and says when it starts and stops.
@MainActor
protocol StepReader: AnyObject, Observable {
    var isSpeaking: Bool { get }
    /// Called on the main actor when speech starts (true) and ends (false).
    var onSpeakingChanged: ((Bool) -> Void)? { get set }

    func speak(_ text: String)
    func stop()
}

/// Rings a timer even when the app is in the background.
@MainActor
protocol TimerAlerts: AnyObject {
    func schedule(_ timer: StepTimer) async
    func cancel(_ id: StepTimer.ID)
}
