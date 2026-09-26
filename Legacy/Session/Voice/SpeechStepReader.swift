import AVFoundation
import Observation

/// Read-aloud with AVSpeechSynthesizer. Start/stop are forwarded from the
/// synthesizer's delegate thread to the main actor through an AsyncStream.
@Observable @MainActor
final class SpeechStepReader: StepReader {
    private(set) var isSpeaking = false
    var onSpeakingChanged: ((Bool) -> Void)?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let relay = SpeechRelay()
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init() {
        synthesizer.delegate = relay
        let events = relay.events
        eventTask = Task { [weak self] in
            for await speaking in events { self?.set(speaking: speaking) }
        }
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func set(speaking: Bool) {
        guard speaking != isSpeaking else { return }
        isSpeaking = speaking
        onSpeakingChanged?(speaking)
    }
}

/// Delegate callbacks arrive on whatever thread AVFoundation likes; only Sendable Bools cross over.
nonisolated private final class SpeechRelay: NSObject, AVSpeechSynthesizerDelegate {
    let events: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation

    override init() {
        let made = AsyncStream.makeStream(of: Bool.self)
        events = made.stream
        continuation = made.continuation
        super.init()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        continuation.yield(true)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        continuation.yield(false)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        continuation.yield(false)
    }
}
