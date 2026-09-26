import Observation
import UIKit

/// The one object the UI talks to. Owns the recipe, where the slideshow is,
/// the ingredient checklist, the timer, and the hands-free bits, all through the
/// protocols in Services/Recipe, Services/Images and Session/Voice.
@Observable @MainActor
final class CookSession {
    enum Phase: Equatable { case empty, working, ready, failed(String) }
    enum Slide: Hashable { case overview, step(Int), done }
    enum Direction { case forward, backward }

    // MARK: Input form

    var linkText = ""
    var transcriptText = ""

    // MARK: State the UI reads

    private(set) var phase: Phase = .empty
    private(set) var recipe: Recipe?
    private(set) var slide: Slide = .overview
    /// Which way the last move went, so the slideshow can animate the right way.
    private(set) var direction: Direction = .forward
    private(set) var checkedIngredients: Set<Int> = []
    private(set) var stepImages: [RecipeStep.ID: UIImage] = [:]
    private(set) var timer: CountdownTimer?
    private(set) var voiceEnabled = false
    /// Speak each slide as it appears. Off: the video's own audio plays for every step, and the
    /// slides carry the words. Kept so it can be switched back on.
    var readAloud = false {
        didSet { if readAloud { speakCurrentSlide() } else { speaker.stopSpeaking() } }
    }
    /// Bumped by "repeat": the video panel plays the current step's part again.
    private(set) var videoReplays = 0
    /// "Skip ahead ten seconds": the video panel moves the player by `seconds`.
    private(set) var videoSkip = VideoSkip(serial: 0, seconds: 0)
    /// "Pause" / "play" said out loud: the video header applies it to the player.
    private(set) var videoPlayback: VideoPlaybackRequest?

    let voice: any VoiceControl
    let speaker: any Speaker
    @ObservationIgnored private let recipes: any RecipeSource
    @ObservationIgnored private let images: any StepImageProvider
    @ObservationIgnored private var imageTask: Task<Void, Never>?
    @ObservationIgnored private var priorityImageTask: Task<Void, Never>?
    @ObservationIgnored private var requestedImages: Set<RecipeStep.ID> = []
    @ObservationIgnored private var voiceTask: Task<Void, Never>?

    init(recipes: any RecipeSource, images: any StepImageProvider, voice: any VoiceControl, speaker: any Speaker) {
        self.recipes = recipes
        self.images = images
        self.voice = voice
        self.speaker = speaker
        voice.onCommand = { [weak self] command in self?.perform(command) }
    }

    /// The real wiring. Each session swaps its implementation in here, one line each.
    static func live() -> CookSession {
        CookSession(recipes: YouTubeRecipeSource.live(),
                    images: RemoteImageProvider.fromInfoPlist() ?? NoStepImages(),
                    voice: SpeechVoiceControl(), speaker: SpeechSynthesizerSpeaker())
    }

    // MARK: Derived

    var steps: [RecipeStep] { recipe?.steps ?? [] }
    var slides: [Slide] { recipe == nil ? [] : [.overview] + steps.indices.map(Slide.step) + [.done] }
    var slideIndex: Int { slides.firstIndex(of: slide) ?? 0 }
    var canGoBack: Bool { slideIndex > 0 }
    var canGoForward: Bool { slideIndex < slides.count - 1 }

    var currentStepIndex: Int? {
        if case .step(let index) = slide, steps.indices.contains(index) { return index }
        return nil
    }
    var currentStep: RecipeStep? { currentStepIndex.map { steps[$0] } }

    /// Kitchen minutes still ahead from where the slideshow is.
    var minutesLeft: Int {
        switch slide {
        case .overview: recipe?.totalMinutes ?? 0
        case .step(let index): recipe?.minutesLeft(from: index) ?? 0
        case .done: 0
        }
    }

    /// The pasted link, normalised to a watch URL; nil until it's a YouTube video link.
    var youtubeURL: URL? { (try? YouTubeLink.videoID(from: linkText)).map(YouTubeLink.watchURL(for:)) }
    var canMakeSlideshow: Bool { youtubeURL != nil && phase != .working }

    // MARK: Loading

    /// Link (+ optional transcript) from the form -> recipe -> slideshow.
    func makeSlideshow() async {
        guard youtubeURL != nil else {
            phase = .failed(RecipeSourceError.notAYouTubeLink.localizedDescription)
            return
        }
        let transcript = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = RecipeRequest(link: linkText, pastedTranscript: transcript.isEmpty ? nil : transcript)
        phase = .working
        do {
            let sourced = try await recipes.recipe(for: request)
            var recipe = sourced.recipe
            // The source knows the video; make sure the recipe carries it for the slides and links.
            if recipe.sourceURL == nil { recipe.sourceURL = sourced.video.watchURL }
            if recipe.thumbnailURL == nil { recipe.thumbnailURL = sourced.video.thumbnailURL }
            if recipe.channel == nil, !sourced.video.channel.isEmpty { recipe.channel = sourced.video.channel }
            if recipe.title.isEmpty { recipe.title = sourced.video.title }
            show(recipe)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// The built-in recipe. Needs no model or network, so it's the safety net on stage.
    func loadDemo() async {
        linkText = Recipe.demo.sourceURL?.absoluteString ?? ""
        show(.demo)
    }

    /// Put a finished recipe on screen, starting at the ingredients slide.
    func show(_ recipe: Recipe) {
        clear()
        self.recipe = recipe
        phase = .ready
        KeepScreenAwake.set(true)
        go(to: .overview, direction: .forward)
        loadImages(for: recipe)
    }

    /// Back to the form. Keeps the link and transcript the cook typed.
    func reset() {
        clear()
        phase = .empty
        KeepScreenAwake.set(false)
    }

    private func clear() {
        imageTask?.cancel(); imageTask = nil
        priorityImageTask?.cancel(); priorityImageTask = nil
        voiceTask?.cancel(); voiceTask = nil
        voice.stopListening()
        voiceEnabled = false
        if let timer { TimerNotifications.shared.cancel(stepID: timer.stepID) }
        requestedImages = []
        speaker.stopSpeaking()
        recipe = nil
        slide = .overview
        direction = .forward
        checkedIngredients = []
        stepImages = [:]
        timer = nil
    }

    // MARK: Navigation

    func next() {
        guard canGoForward else { return }
        go(to: slides[slideIndex + 1], direction: .forward)
    }

    func previous() {
        guard canGoBack else { return }
        go(to: slides[slideIndex - 1], direction: .backward)
    }

    func goToStep(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        go(to: .step(index))
    }

    func go(to target: Slide) {
        let targetIndex = slides.firstIndex(of: target) ?? 0
        go(to: target, direction: targetIndex >= slideIndex ? .forward : .backward)
    }

    private func go(to target: Slide, direction: Direction) {
        guard slides.contains(target) else { return }
        self.direction = direction
        slide = target
        prioritizeImage(for: currentStep)
        speakCurrentSlide()
    }

    /// Play the current step's part of the video again; without a video, say the slide instead.
    func repeatStep() {
        if recipe?.videoID != nil, currentStep != nil {
            videoReplays += 1
        } else {
            speakCurrentSlide(force: true)
        }
    }

    // MARK: Ingredients

    func toggleIngredient(_ index: Int) {
        if checkedIngredients.contains(index) { checkedIngredients.remove(index) } else { checkedIngredients.insert(index) }
    }

    var allIngredientsChecked: Bool {
        guard let recipe, !recipe.ingredients.isEmpty else { return false }
        return checkedIngredients.count == recipe.ingredients.count
    }

    // MARK: Timer

    /// Starts the one timer from the current step's kitchen minutes, replacing any running one.
    func startTimer() {
        guard let step = currentStep else { return }
        if let old = timer { TimerNotifications.shared.cancel(stepID: old.stepID) }
        let started = CountdownTimer(step: step, secondsPerMinute: Self.secondsPerMinute)
        timer = started
        Task { await TimerNotifications.shared.schedule(started) }
    }

    func stopTimer() {
        if let old = timer { TimerNotifications.shared.cancel(stepID: old.stepID) }
        timer = nil
    }

    /// Real seconds per recipe minute. Debug builds honour COOKALONG_SECONDS_PER_MINUTE
    /// (for example "1") so a 9-minute timer can be tried in 9 seconds.
    private static let secondsPerMinute: Double = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["COOKALONG_SECONDS_PER_MINUTE"],
           let value = Double(raw), value > 0 { return value }
        #endif
        return 60
    }()

    // MARK: Voice

    func setVoice(enabled: Bool) {
        voiceEnabled = enabled
        voiceTask?.cancel()
        if enabled {
            voiceTask = Task { await voice.startListening() }
        } else {
            voice.stopListening()
        }
    }

    /// A phrase as if the mic had heard it: matched like speech, then performed. Lets a text
    /// field, a test or a debug script drive the same commands the voice does.
    @discardableResult
    func say(_ phrase: String) -> VoiceCommand? {
        guard let command = CommandMatcher.match(phrase) else { return nil }
        perform(command)
        return command
    }

    private func perform(_ command: VoiceCommand) {
        NSLog("COOKALONG-VOICE %@", command.label)
        switch command {
        case .next:       next()
        case .back:       previous()
        case .repeatStep: repeatStep()
        case .startTimer: startTimer()
        case .stopTimer:  stopTimer()
        case .skip(let seconds): skipVideo(by: seconds)
        case .pauseVideo: setVideo(playing: false)
        case .playVideo:  setVideo(playing: true)
        case .goToStep(let number): goToSpokenStep(number)
        case .ingredients: go(to: .overview)
        case .whatDoINeed: speakNeeds()
        case .timeLeft:    speakTimeLeft()
        }
    }

    // MARK: Video timeline

    /// Moves the video by `seconds` (negative goes back); nothing happens without a video.
    func skipVideo(by seconds: Int) {
        guard recipe?.videoID != nil, seconds != 0 else { return }
        videoSkip = VideoSkip(serial: videoSkip.serial + 1, seconds: seconds)
        NSLog("COOKALONG-VIDEO skip %d s", seconds)
    }

    func setVideo(playing: Bool) {
        guard recipe?.videoID != nil else { return }
        videoPlayback = VideoPlaybackRequest(serial: (videoPlayback?.serial ?? 0) + 1, play: playing)
        NSLog("COOKALONG-VIDEO %@", playing ? "play" : "pause")
    }

    /// "Go to step three": one-based; out of range says so instead of doing nothing silently.
    func goToSpokenStep(_ number: Int) {
        let index = number - 1
        if steps.indices.contains(index) {
            goToStep(index)
        } else if !steps.isEmpty {
            speaker.speak("There are \(steps.count) steps.")
        }
    }

    // MARK: Spoken answers

    /// "What do I need": the current step's ingredients with their amounts.
    func speakNeeds() {
        guard let step = currentStep else {
            if let recipe, slide == .overview {
                speaker.speak("You need \(recipe.ingredients.joined(separator: ", ")).")
            }
            return
        }
        let needs = StepNeeds.needs(for: step)
        if needs.isEmpty {
            speaker.speak("Nothing to get out for this step.")
        } else {
            let list = needs.map { [$0.amount, $0.label].compactMap { $0 }.joined(separator: " ") }
            speaker.speak("You need \(list.joined(separator: ", ")).")
        }
    }

    /// "How long": the timer's remaining time, or the step's kitchen minutes when none is running.
    func speakTimeLeft() {
        if let timer {
            let remaining = Int(timer.remaining(at: .now).rounded())
            if remaining <= 0 {
                speaker.speak("The timer is done.")
            } else {
                let minutes = remaining / 60, seconds = remaining % 60
                var parts: [String] = []
                if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
                if seconds > 0 || minutes == 0 { parts.append("\(seconds) second\(seconds == 1 ? "" : "s")") }
                speaker.speak("\(parts.joined(separator: " and ")) left.")
            }
        } else if let step = currentStep {
            speaker.speak("No timer running. This step takes about \(step.minutes) minute\(step.minutes == 1 ? "" : "s").")
        } else if let recipe {
            speaker.speak("About \(recipe.totalMinutes) minutes in all.")
        }
    }

    // MARK: Read-aloud

    private func speakCurrentSlide(force: Bool = false) {
        guard readAloud || force, let recipe else { return }
        speaker.speak(spokenText(for: slide, in: recipe))
    }

    /// What read-aloud says for a slide.
    func spokenText(for slide: Slide, in recipe: Recipe) -> String {
        switch slide {
        case .overview:
            return "\(recipe.title). Serves \(recipe.servings). You'll need: \(recipe.ingredients.joined(separator: ", "))."
        case .step(let index):
            let step = recipe.steps[index]
            let tip = step.tip.isEmpty ? "" : " Tip: \(step.tip)"
            return "Step \(index + 1) of \(recipe.steps.count). \(step.title). \(step.instruction)\(tip)"
        case .done:
            return "That's it. Enjoy your \(recipe.title)."
        }
    }

    // MARK: Images

    private func loadImages(for recipe: Recipe) {
        imageTask = Task {
            for step in recipe.steps {
                if Task.isCancelled { return }
                await fetchImage(for: step, in: recipe)
            }
        }
    }

    /// The step on screen jumps the queue.
    private func prioritizeImage(for step: RecipeStep?) {
        guard let step, let recipe, !requestedImages.contains(step.id) else { return }
        priorityImageTask = Task { await fetchImage(for: step, in: recipe) }
    }

    private func fetchImage(for step: RecipeStep, in recipe: Recipe) async {
        guard !requestedImages.contains(step.id) else { return }
        requestedImages.insert(step.id)
        if let image = await images.image(for: step, in: recipe), !Task.isCancelled, self.recipe?.id == recipe.id {
            stepImages[step.id] = image
        }
    }
}
