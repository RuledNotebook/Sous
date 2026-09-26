import AVFoundation
import Observation
import UIKit
import os

/// The one object the UI talks to. Owns the player, the recipe, the sync
/// between video time and the current step, and everything hands-free:
/// voice commands, read-aloud, multiple timers, keep-awake.
@Observable @MainActor
final class CookSession {
    enum Phase: Equatable { case empty, transcribing, analyzing, ready, failed(String) }

    // State the UI reads
    var phase: Phase = .empty { didSet { phaseDidChange() } }
    var recipe: Recipe?
    var currentIndex = 0
    var currentTime: Double = 0
    var videoDuration: Double = 0
    var pauseAtEachStep = true
    var stepImages: [RecipeStep.ID: UIImage] = [:]

    // Hands-free
    /// Every running (or finished but not yet dismissed) timer, oldest first.
    private(set) var timers: [StepTimer] = []
    /// The cook's intent. `voice.state` says whether we're actually hearing anything.
    private(set) var voiceControlEnabled = false
    /// Speak each step as it begins. Remembered between launches.
    var readAloud = UserDefaults.standard.bool(forKey: readAloudKey) {
        didSet {
            UserDefaults.standard.set(readAloud, forKey: Self.readAloudKey)
            if readAloud { speakCurrentStep() } else { speaker.stop() }
        }
    }
    let voice: any VoiceControl
    let speaker: any StepReader

    let player = AVPlayer()
    private(set) var videoURL: URL?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private let imageLoader: StepImageLoader
    @ObservationIgnored private var timerWatchers: [StepTimer.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var lifecycleObservers: [any NSObjectProtocol] = []
    /// While set, playback stops just before this time (end of the step being repeated).
    @ObservationIgnored private var replayEnd: Double?
    @ObservationIgnored private let notifier: any TimerAlerts
    @ObservationIgnored private let transcriber: any TranscriptService
    @ObservationIgnored private let analyzer: any RecipeAnalyzer
    @ObservationIgnored private let images: any StepImageProvider
    @ObservationIgnored private let log = Logger(subsystem: "com.cookalong.CookAlong", category: "session")

    private static let readAloudKey = "cookalong.readAloud"
    /// Real seconds per recipe minute. Debug builds honour COOKALONG_SECONDS_PER_MINUTE
    /// (e.g. "1") so a 9-minute pasta timer can be tested in 9 seconds.
    private static let secondsPerMinute: Double = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["COOKALONG_SECONDS_PER_MINUTE"],
           let value = Double(raw), value > 0 { return value }
        #endif
        return 60
    }()

    /// The production voice stack; previews and tests pass their own through the full initializer.
    convenience init(transcriber: any TranscriptService, analyzer: any RecipeAnalyzer, images: any StepImageProvider) {
        self.init(transcriber: transcriber, analyzer: analyzer, images: images,
                  voice: SpeechVoiceControl(), reader: SpeechStepReader(), alerts: LocalTimerAlerts())
    }

    init(transcriber: any TranscriptService, analyzer: any RecipeAnalyzer, images: any StepImageProvider,
         voice: any VoiceControl, reader: any StepReader, alerts: any TimerAlerts) {
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.images = images
        self.voice = voice
        self.speaker = reader
        self.notifier = alerts
        imageLoader = StepImageLoader(provider: images)
        AudioSessionController.activatePlayback()
        voice.onCommand = { [weak self] command in self?.perform(command) }
        speaker.onSpeakingChanged = { [weak self] speaking in self?.speakingDidChange(speaking) }
        observeLifecycle()
        #if DEBUG
        // Launch arguments for simulator runs (see App/DebugLaunchOptions.swift for the others):
        //   -autoVoice YES       turn voice control on as soon as a recipe is open
        //   -autoReadAloud YES   turn read-aloud on (NO turns it off)
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "autoVoice") { voiceControlEnabled = true }
        if defaults.object(forKey: "autoReadAloud") != nil { readAloud = defaults.bool(forKey: "autoReadAloud") }
        #endif
    }

    static func live() -> CookSession {
        CookSession(
            transcriber: SpeechTranscriptService(),
            analyzer: RoutingRecipeAnalyzer.live(),
            images: FallbackImageProvider(primary: RemoteImageProvider.fromInfoPlist(),
                                          fallback: VideoFrameImageProvider()),
            voice: SpeechVoiceControl(), reader: SpeechStepReader(), alerts: LocalTimerAlerts()
        )
    }

    var currentStep: RecipeStep? {
        guard let recipe, recipe.steps.indices.contains(currentIndex) else { return nil }
        return recipe.steps[currentIndex]
    }

    // MARK: Loading

    /// Bundled demo.mp4 + hard-coded recipe. Use this on stage.
    func loadDemo() async {
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "mp4") else {
            phase = .failed("Add a demo.mp4 to the app target to use the demo.")
            return
        }
        await load(videoURL: url, knownRecipe: .demo)
    }

    func load(videoURL: URL, knownRecipe: Recipe? = nil) async {
        reset()
        self.videoURL = videoURL
        player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
        attachTimeObserver()
        videoDuration = (try? await AVURLAsset(url: videoURL).load(.duration).seconds) ?? 0

        do {
            let result: Recipe
            if let knownRecipe {
                result = knownRecipe
            } else {
                phase = .transcribing
                let lines = try await transcriber.transcript(for: videoURL)
                phase = .analyzing
                result = try await analyzer.recipe(from: lines, videoDuration: videoDuration)
            }
            recipe = result
            phase = .ready
            loadImages(for: result)
            stepDidBegin()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func reset() {
        imageLoader.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        speaker.stop()
        recipe = nil
        stepImages = [:]
        currentIndex = 0
        currentTime = 0
        replayEnd = nil
        // Timers keep running: a pasta timer shouldn't die because you opened another video.
    }

    /// Cached pictures first, then video frames, then AI images replacing them; the step on screen always next.
    private func loadImages(for recipe: Recipe) {
        imageLoader.start(recipe: recipe, videoURL: videoURL,
                          currentIndex: { [weak self] in self?.currentIndex ?? 0 },
                          onImage: { [weak self] id, image in self?.stepImages[id] = image })
    }

    // MARK: Video <-> step sync

    private func attachTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private func tick(_ seconds: Double) {
        currentTime = seconds
        guard let recipe else { return }
        // Repeating a step: hold just before the next step starts so the card stays put.
        if let end = replayEnd, seconds >= end - 0.35 {
            replayEnd = nil
            player.pause()
            return
        }
        let index = recipe.stepIndex(at: seconds)
        guard index != currentIndex else { return }
        // Crossed into the next step while playing: hold so the cook can catch up.
        if index > currentIndex, pauseAtEachStep, player.rate > 0 { player.pause() }
        currentIndex = index
        stepDidBegin()
    }

    // MARK: Navigation

    func goTo(_ index: Int) {
        guard let recipe, recipe.steps.indices.contains(index) else { return }
        replayEnd = nil
        let changed = index != currentIndex
        currentIndex = index
        let t = CMTime(seconds: recipe.steps[index].videoStart, preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        if changed { stepDidBegin() }
    }

    func next()     { goTo(currentIndex + 1) }
    func previous() { goTo(currentIndex - 1) }
    func play()     { player.play() }
    func pause()    { player.pause() }

    /// Replays the current step's slice of the video from its start, then holds at its end.
    func repeatStep() {
        guard let recipe, let step = currentStep else { return }
        let nextIndex = currentIndex + 1
        replayEnd = recipe.steps.indices.contains(nextIndex) ? recipe.steps[nextIndex].videoStart : nil
        let start = CMTime(seconds: step.videoStart, preferredTimescale: 600)
        Task {
            await player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        }
    }

    /// A new step is on screen: say it if read-aloud is on.
    private func stepDidBegin() {
        if readAloud { speakCurrentStep() }
    }

    // MARK: Voice control

    func setVoiceControl(_ enabled: Bool) {
        voiceControlEnabled = enabled
        syncVoice()
    }

    private func syncVoice() {
        if voiceControlEnabled, phase == .ready {
            Task { await voice.start() }
        } else if voice.state != .off {
            voice.stop()
        }
    }

    private func perform(_ command: VoiceCommand) {
        log.info("voice: \(command.label, privacy: .public)")
        switch command {
        case .next:       next()
        case .back:       previous()
        case .repeatStep: repeatStep()
        case .pause:      pause()
        case .play:       play()
        case .startTimer: startTimer()
        case .stopTimer:  stopTimer()
        }
    }

    // MARK: Read-aloud

    private func speakCurrentStep() {
        guard let recipe, let step = currentStep else { return }
        speaker.speak("Step \(currentIndex + 1) of \(recipe.steps.count). \(step.title). \(step.instruction)")
    }

    /// Duck the video under the voice, and stop listening to ourselves.
    private func speakingDidChange(_ speaking: Bool) {
        voice.muted = speaking
        player.volume = speaking ? 0.15 : 1
        log.info("read-aloud \(speaking ? "started, video ducked" : "finished, video restored", privacy: .public)")
    }

    // MARK: Timers

    /// The current step's timer, if one is running or just finished.
    var currentStepTimer: StepTimer? {
        guard let step = currentStep else { return nil }
        return timers.first { $0.stepID == step.id }
    }

    /// Timers for other steps (the pasta while you sear the shrimp).
    var otherTimers: [StepTimer] {
        timers.filter { $0.stepID != currentStep?.id }
    }

    // Kept for the original single-timer UI.
    var timerEnds: Date? { currentStepTimer?.ends }
    var timerLength: TimeInterval { currentStepTimer?.length ?? 0 }

    func startTimer() {
        guard let step = currentStep else { return }
        startTimer(for: step)
    }

    func startTimer(for step: RecipeStep) {
        if let existing = timers.first(where: { $0.stepID == step.id }) {
            guard existing.isDone else { return }   // already running for this step
            stopTimer(existing.id)                   // finished and still on screen: start afresh
        }
        let timer = StepTimer(step: step, length: Double(max(step.minutes, 1)) * Self.secondsPerMinute)
        timers.append(timer)
        Task { await notifier.schedule(timer) }
        timerWatchers[timer.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timer.remaining()))
            guard !Task.isCancelled else { return }
            self?.timerDidFinish(timer)
        }
        log.info("timer started: \(timer.title, privacy: .public) (\(Int(timer.length))s)")
    }

    /// Stops the timer that needs it most: one that's ringing, else this step's, else the oldest.
    func stopTimer() {
        guard let timer = timers.first(where: \.isDone) ?? currentStepTimer ?? timers.first else { return }
        stopTimer(timer.id)
    }

    func stopTimer(_ id: StepTimer.ID) {
        timers.removeAll { $0.id == id }
        timerWatchers.removeValue(forKey: id)?.cancel()
        notifier.cancel(id)
    }

    private func timerDidFinish(_ timer: StepTimer) {
        timerWatchers.removeValue(forKey: timer.id)
        guard timers.contains(where: { $0.id == timer.id }) else { return }
        log.info("timer finished: \(timer.title, privacy: .public)")
        if readAloud { speaker.speak("Time's up. \(timer.title).") }
    }

    // MARK: Screen + lifecycle

    private func phaseDidChange() {
        // Keep the screen awake while a recipe is open.
        UIApplication.shared.isIdleTimerDisabled = phase == .ready
        log.info("phase \(String(describing: self.phase), privacy: .public); screen stays awake: \(self.phase == .ready)")
        syncVoice()
    }

    /// The mic can't run in the background; drop it there and pick it back up on return.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.voice.state != .off else { return }
                self.voice.stop()
            }
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncVoice()
                if let self, self.phase == .ready { UIApplication.shared.isIdleTimerDisabled = true }
            }
        })
    }
}
