import AVFoundation
import Observation
import Speech
import UIKit
import os

/// Listens on the mic and turns "next", "back", "repeat", "start timer", "stop timer"
/// into `VoiceCommand`s, for as long as the cook keeps it on.
///
/// - Recognition: SFSpeechRecognizer, on-device when the device has the assets
///   (`requiresOnDeviceRecognition`), the server otherwise (the simulator). A fresh task starts
///   after every command, whenever a task ends, after read-aloud finishes, and every 45 s, so
///   listening never stops and the transcript never grows unbounded.
/// - Only words that arrived since the last command are looked at; a second command within
///   one second is dropped.
/// - The audio tap and the recognition callbacks run off the main thread. They hand over
///   plain Sendable values (`AudioRelay`, `RecognitionEvent`) and hop to the main actor
///   before touching any state.
/// - While `SpeechSynthesizerSpeaker` talks (see `ReadAloudGate`) everything heard is dropped,
///   and voice processing on the input node cancels the echo on top of that.
@Observable @MainActor
final class SpeechVoiceControl: VoiceControl {
    private(set) var status: VoiceStatus = .off
    private(set) var heard = ""
    var onCommand: ((VoiceCommand) -> Void)?

    /// The last command and when it fired, for a "Heard: next" chip.
    private(set) var lastCommand: VoiceCommand?
    private(set) var lastCommandAt: Date?

    // Tuning
    private static let debounce: TimeInterval = 1.0
    private static let refreshEvery: TimeInterval = 45
    private static let maxSegments = 40

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let audio = AudioRelay()
    @ObservationIgnored private let gate = ReadAloudGate.shared
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var consumedWords = 0
    @ObservationIgnored private var restartWork: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var preferOnDevice = true
    @ObservationIgnored private var useVoiceProcessing = true
    @ObservationIgnored private var failureStreak = 0
    @ObservationIgnored private var interruptionObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let log = Logger(subsystem: "com.cookalong.CookAlong", category: "voice")

    enum VoiceError: LocalizedError {
        case noMicrophone
        var errorDescription: String? { "No microphone input is available." }
    }

    #if DEBUG
    /// Debug only: launch with `-voiceInputFile /path/to/audio` and that file is streamed into
    /// recognition in real time instead of the mic, so every command can be exercised on a
    /// simulator without touching the Mac's audio hardware. Nothing here ships.
    @ObservationIgnored private var fileFeeder: Task<Void, Never>?
    private var debugInputURL: URL? {
        guard let path = UserDefaults.standard.string(forKey: "voiceInputFile"), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
    #endif

    init() {
        // Read-aloud starts: stop looking at input. Ends: wait out the grace period, then listen afresh.
        gate.onChange { [weak self] speaking in self?.speakingDidChange(speaking) }
    }

    private func speakingDidChange(_ speaking: Bool) {
        guard status == .listening else { return }
        if speaking {
            heard = ""
        } else {
            scheduleRestart(after: gate.grace)
        }
    }

    // MARK: Lifecycle

    func startListening() async {
        guard status != .listening, status != .starting else { return }
        status = .starting
        guard await Self.requestSpeechAuthorization() == .authorized else {
            log.notice("speech recognition denied")
            status = .denied
            return
        }
        #if DEBUG
        if let debugInputURL {
            guard let recognizer, recognizer.isAvailable else { status = .unavailable; return }
            status = .listening
            failureStreak = 0
            beginTask()
            feed(debugInputURL)
            log.info("listening to file \(debugInputURL.lastPathComponent, privacy: .public) instead of the mic")
            return
        }
        #endif
        guard await AVAudioApplication.requestRecordPermission() else {
            log.notice("microphone denied")
            status = .denied
            return
        }
        guard let recognizer, recognizer.isAvailable else { status = .unavailable; return }
        do {
            try AudioSessionController.activateRecording()
            try startEngine()
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
            AudioSessionController.activatePlayback()
            return
        }
        status = .listening
        failureStreak = 0
        observeInterruptions()
        beginTask()
        startWatchdog()
        log.info("listening (on-device: \(recognizer.supportsOnDeviceRecognition), voice processing: \(self.useVoiceProcessing))")
    }

    func stopListening() {
        generation += 1
        restartWork?.cancel()
        watchdog?.cancel()
        #if DEBUG
        fileFeeder?.cancel()
        fileFeeder = nil
        #endif
        task?.cancel()
        task = nil
        audio.swap(nil)?.endAudio()
        stopEngine()
        status = .off
        heard = ""
        AudioSessionController.activatePlayback()
        log.info("stopped")
    }

    // MARK: Engine

    private func startEngine() throws {
        let input = engine.inputNode
        if useVoiceProcessing {
            // Echo cancellation: the video's narration and our own read-aloud shouldn't trigger commands.
            do { try input.setVoiceProcessingEnabled(true) } catch {
                useVoiceProcessing = false
                log.notice("voice processing unavailable: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            try? input.setVoiceProcessingEnabled(false)
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.noMicrophone }
        if !tapInstalled {
            let audio = audio
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                audio.deliver(buffer)          // realtime thread: touches no main-actor state
            }
            tapInstalled = true
        }
        engine.prepare()
        try engine.start()
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    /// Voice processing can silently deliver no audio on some setups. If nothing arrives in
    /// the first seconds, fall back to the plain input and carry on.
    private func startWatchdog() {
        watchdog?.cancel()
        let gen = generation
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled, self.status == .listening, self.generation == gen else { return }
            let buffers = self.audio.buffersDelivered
            self.log.info("audio buffers in first seconds: \(buffers)")
            guard buffers == 0, self.useVoiceProcessing else { return }
            self.log.notice("no audio with voice processing on; restarting without it")
            self.useVoiceProcessing = false
            self.stopEngine()
            do { try self.startEngine() } catch { self.status = .failed(error.localizedDescription); return }
            self.beginTask()
        }
    }

    // MARK: Recognition

    /// Starts a fresh recognition task; the old one is cancelled and its late results ignored.
    private func beginTask() {
        guard let recognizer, status == .listening else { return }
        generation += 1
        let gen = generation
        consumedWords = 0
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = CommandMatcher.allPhrases
        if preferOnDevice, recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        audio.swap(request)?.endAudio()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Recognizer thread: snapshot Sendable values only, then hop to the main actor.
            let event = RecognitionEvent(text: result?.bestTranscription.formattedString,
                                         segments: result?.bestTranscription.segments.count ?? 0,
                                         isFinal: result?.isFinal ?? false,
                                         error: error?.localizedDescription)
            Task { @MainActor in self?.handle(event, generation: gen) }
        }
        scheduleRestart(after: Self.refreshEvery, generation: gen)
    }

    private func scheduleRestart(after seconds: TimeInterval, generation gen: Int? = nil) {
        restartWork?.cancel()
        let expected = gen ?? generation
        restartWork = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.status == .listening, self.generation == expected else { return }
            if !self.engine.isRunning, self.tapInstalled { try? self.engine.start() }
            self.beginTask()
        }
    }

    private func handle(_ event: RecognitionEvent, generation gen: Int) {
        guard gen == generation, status == .listening else { return }
        if let text = event.text {
            failureStreak = 0
            // The app is talking (or just stopped): drop what we hear; a fresh task starts after the grace period.
            if gate.shouldIgnoreInput() {
                log.debug("ignored while speaking: \(text, privacy: .public)")
                return
            }
            heard = String(text.suffix(48))
            log.debug("heard: \(text, privacy: .public)")
            // Only words that arrived since the last command count.
            let words = CommandMatcher.tokenize(text)
            guard words.count > consumedWords else { return }
            if let match = CommandMatcher.match(Array(words[consumedWords...])) {
                consumedWords += match.end
                fire(match.command)
                beginTask()
                return
            }
            if event.isFinal || event.segments > Self.maxSegments { beginTask(); return }
        }
        if let error = event.error {
            failureStreak += 1
            log.debug("recognition ended (\(self.failureStreak)): \(error, privacy: .public)")
            if failureStreak == 3, preferOnDevice {
                preferOnDevice = false
                log.notice("falling back to server recognition")
            } else if failureStreak > 8 {
                status = .failed(error)
                return
            }
            scheduleRestart(after: 0.4, generation: gen)
        }
    }

    private func fire(_ command: VoiceCommand) {
        if let last = lastCommandAt, Date.now.timeIntervalSince(last) < Self.debounce {
            log.debug("debounced: \(command.label, privacy: .public)")
            return
        }
        lastCommand = command
        lastCommandAt = .now
        log.info("command: \(command.label, privacy: .public)")
        onCommand?(command)
    }

    // MARK: Interruptions (calls, Siri)

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let self else { return }
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = raw.flatMap(AVAudioSession.InterruptionType.init)
            Task { @MainActor in self.handleInterruption(type) }
        }
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began:
            engine.pause()
        case .ended:
            guard status == .listening else { return }
            try? AudioSessionController.activateRecording()
            try? engine.start()
            beginTask()
        default:
            break
        }
    }

    #if DEBUG
    /// Streams the file's PCM at real-time pace through the same relay the mic tap uses.
    private func feed(_ url: URL) {
        fileFeeder?.cancel()
        let audio = audio
        fileFeeder = Task.detached {
            guard let file = try? AVAudioFile(forReading: url) else { return }
            let format = file.processingFormat
            let chunk: AVAudioFrameCount = 4096
            let pace = Double(chunk) / format.sampleRate
            while !Task.isCancelled {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
                do { try file.read(into: buffer, frameCount: chunk) } catch { return }
                if buffer.frameLength == 0 { return }
                audio.deliver(buffer)
                try? await Task.sleep(for: .seconds(pace))
            }
        }
    }
    #endif

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
    }
}

/// What a recognition callback hands to the main actor: plain values only.
nonisolated private struct RecognitionEvent: Sendable {
    let text: String?
    let segments: Int
    let isFinal: Bool
    let error: String?
}

/// Shared between the realtime audio tap and the main actor: the request that should receive
/// audio right now, plus a buffer count for the voice-processing watchdog.
nonisolated private final class AudioRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var delivered = 0

    var buffersDelivered: Int { lock.withLock { delivered } }

    func deliver(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            delivered += 1
            request?.append(buffer)
        }
    }

    @discardableResult
    func swap(_ new: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.withLock { let old = request; request = new; return old }
    }
}
