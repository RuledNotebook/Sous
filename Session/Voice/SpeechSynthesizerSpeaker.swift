import AVFoundation
import Observation

/// Read-aloud with AVSpeechSynthesizer. While it talks, `ReadAloudGate` keeps the mic from
/// hearing it. Delegate callbacks arrive on the synthesizer's thread and are forwarded to the
/// main actor as plain Bools through an AsyncStream.
@Observable @MainActor
final class SpeechSynthesizerSpeaker: Speaker {
    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let relay = SpeechRelay(gate: .shared)
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init() {
        synthesizer.delegate = relay
        let events = relay.events
        eventTask = Task { [weak self] in
            for await speaking in events { self?.isSpeaking = speaking }
        }
    }

    /// Replaces whatever is currently being said.
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

/// Raises and lowers the gate on the delegate thread (no main-actor state), then relays a Bool.
nonisolated private final class SpeechRelay: NSObject, AVSpeechSynthesizerDelegate {
    let events: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private let gate: ReadAloudGate

    init(gate: ReadAloudGate) {
        let made = AsyncStream.makeStream(of: Bool.self)
        events = made.stream
        continuation = made.continuation
        self.gate = gate
        super.init()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        gate.speechDidStart()
        continuation.yield(true)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        gate.speechDidEnd()
        continuation.yield(false)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        gate.speechDidEnd()
        continuation.yield(false)
    }
}
