import Foundation
import FoundationModels

@MainActor
protocol RecipeAnalyzer {
    func recipe(from transcript: [TranscriptLine], videoDuration: Double) async throws -> Recipe
}

// MARK: - Structured output schema for the on-device model
//
// Guides verified against the iOS 27.0 SDK FoundationModels.swiftinterface:
//   String: .anyOf([String]), .constant, .pattern   Int: .range(ClosedRange<Int>), .minimum, .maximum
//   [T]:    .maximumCount(Int), .minimumCount, .count, .element
// The @Guide macro takes `description:` plus zero or more GenerationGuide<T> values.

/// One window's worth of steps. Kept small so instructions + schema + output fit the ~4k context.
@Generable
nonisolated struct GeneratedWindow {
    @Guide(description: "Ingredients mentioned in this section, with amounts if spoken, e.g. '200 g spaghetti'. Empty if none.", .maximumCount(12))
    var ingredients: [String]
    @Guide(description: "Cooking steps whose action begins in this section, in video order. Empty if nothing is cooked here.", .maximumCount(8))
    var steps: [GeneratedStep]
}

@Generable
nonisolated struct GeneratedStep {
    @Guide(description: "2 to 5 word step title starting with a verb")
    var title: String
    @Guide(description: "One or two clear sentences a home cook can follow")
    var instruction: String
    @Guide(description: "The [Ns] timestamp of the line where the cook physically starts this action, not where it is first mentioned or planned", .minimum(0))
    var startSecond: Int
    @Guide(description: "Real kitchen minutes for this step, never video time. Use a spoken duration if there is one.", .range(1...240))
    var minutes: Int
    @Guide(description: "true if the cook is actively working, false if waiting (boiling, baking, resting)")
    var isHandsOn: Bool
    @Guide(description: "true if the step needs a countdown timer")
    var needsTimer: Bool
    @Guide(description: "One short practical tip, or an empty string")
    var tip: String
    @Guide(description: "Visual description of the finished state of this step for an image generator, no people or text")
    var imagePrompt: String
}

/// Second, tiny pass once all steps are known: name the dish and tidy the ingredient list.
@Generable
nonisolated struct GeneratedRecipeMeta {
    @Guide(description: "Short name of the dish, e.g. 'Garlic butter shrimp pasta'")
    var title: String
    @Guide(description: "How many people it serves", .range(1...12))
    var servings: Int
    @Guide(description: "Overall difficulty", .anyOf(["easy", "medium", "hard"]))
    var difficulty: String
    @Guide(description: "Final ingredient list: one entry per ingredient, duplicates merged, amounts kept", .maximumCount(25))
    var ingredients: [String]
}

nonisolated extension StepCandidate {
    init(_ g: GeneratedStep) {
        self.init(title: g.title, instruction: g.instruction, startSecond: Double(g.startSecond),
                  minutes: g.minutes, isHandsOn: g.isHandsOn, needsTimer: g.needsTimer,
                  tip: g.tip, imagePrompt: g.imagePrompt)
    }
}

// MARK: - Prompts (shared by the on-device and cloud analyzers)

nonisolated enum RecipePrompts {
    /// Rules plus two short worked examples: one for where a step's timestamp lands, one for
    /// kitchen minutes when the video jump-cuts. Kept terse; every token here is paid per window.
    static let rules = """
        Each transcript line starts with the second it was spoken, like [42s].

        startSecond: the second the cook physically BEGINS the action, not when it is first \
        mentioned or planned. Copy the timestamp of the line where the action starts.
        Example:
        [12s] First thing, we need the onions diced nice and small.
        [20s] Actually let me get the pan heating first, medium high.
        [31s] Okay, pan's on. Now the onion, I like a fine dice.
        -> "Heat the pan" startSecond 20; "Dice the onion" startSecond 31 (not 12, that was just talk).

        minutes: real kitchen time, never video time. Videos skip the waiting.
        Example:
        [140s] Into the oven at 200 degrees for 25 minutes.
        [143s] And here it is out of the oven, look at that colour.
        -> "Bake the dish" minutes 25, isHandsOn false, needsTimer true.
        If a duration is spoken, use it. Otherwise estimate what a home cook needs \
        (dice an onion 3 min, bring a pot to the boil 8 min).

        Merge chatter and repeated mentions into real cooking steps. Skip intros, sponsor talk \
        and outros. Steps stay in video order.
        """

    static let windowInstructions = """
        You turn one section of a cooking video transcript into cooking steps.
        \(rules)
        List only ingredients mentioned in this section, with amounts if spoken. \
        If nothing is cooked in this section, return no steps.
        """

    static func windowPrompt(_ window: TranscriptWindow, videoDuration: Double) -> String {
        let total = Int(videoDuration.rounded())
        let from = Int(window.startSecond), to = Int(window.endSecond.rounded())
        let span = total > 0 ? "Video length: \(total) seconds. " : ""
        return "\(span)This section covers \(from)s to \(to)s.\nTranscript:\n\(window.rendered)"
    }

    static let metadataInstructions = """
        You are given the steps and ingredients extracted from a cooking video. \
        Name the dish, estimate servings and difficulty, and return one clean ingredient list \
        with duplicates merged and amounts kept.
        """

    static func metadataPrompt(stepTitles: [String], ingredients: [String]) -> String {
        let steps = stepTitles.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let list = ingredients.isEmpty ? "(none mentioned)" : ingredients.joined(separator: "; ")
        return "Steps:\n\(steps)\n\nIngredients mentioned:\n\(list)"
    }

    static let cloudInstructions = """
        You turn cooking video transcripts into step-by-step recipes and answer only with JSON \
        matching the given schema.
        \(rules)
        Give the dish a short title, estimate servings and difficulty (easy, medium or hard), \
        and list every ingredient once with amounts if spoken. Each step needs a 2-5 word title \
        starting with a verb, one or two clear sentences, startSecond, minutes, isHandsOn, \
        needsTimer, a short tip (or empty string) and an imagePrompt describing the finished \
        state of the step for an image generator with no people or text.
        """
}

// MARK: - Apple Intelligence (on-device) implementation

/// Chunked on-device analysis. The system model's context is ~4k tokens, so the transcript is
/// split into windows (see `ChunkedRecipePipeline`); a window that still overflows is halved
/// and retried. A fresh session per window keeps earlier windows out of the context.
struct OnDeviceRecipeAnalyzer: RecipeAnalyzer {
    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: true
        default: false
        }
    }

    /// Human-readable reason when `isAvailable` is false, for status UI.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings."
        case .unavailable(.modelNotReady): "The on-device model is still downloading."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    var pipeline = ChunkedRecipePipeline()

    func recipe(from transcript: [TranscriptLine], videoDuration: Double) async throws -> Recipe {
        guard Self.isAvailable else {
            throw RecipeAnalysisError.modelUnavailable(Self.unavailableReason ?? "unknown")
        }
        return try await pipeline.run(transcript: transcript, videoDuration: videoDuration,
                                      extractor: FoundationModelsWindowExtractor(videoDuration: videoDuration),
                                      metadata: FoundationModelsMetadataProvider())
    }
}

struct FoundationModelsWindowExtractor: WindowExtractor {
    var videoDuration: Double

    func extract(_ window: TranscriptWindow) async throws -> ExtractedWindow {
        let session = LanguageModelSession(instructions: RecipePrompts.windowInstructions)
        let prompt = RecipePrompts.windowPrompt(window, videoDuration: videoDuration)
        do {
            let generated = try await session.respond(to: prompt, generating: GeneratedWindow.self,
                                                      options: GenerationOptions(samplingMode: .greedy)).content
            return ExtractedWindow(steps: generated.steps.map(StepCandidate.init), ingredients: generated.ingredients)
        } catch {
            throw FoundationModelsErrors.translate(error)
        }
    }
}

struct FoundationModelsMetadataProvider: RecipeMetadataProvider {
    func metadata(stepTitles: [String], ingredients: [String]) async throws -> RecipeMetadata {
        let session = LanguageModelSession(instructions: RecipePrompts.metadataInstructions)
        let prompt = RecipePrompts.metadataPrompt(stepTitles: stepTitles, ingredients: ingredients)
        do {
            let g = try await session.respond(to: prompt, generating: GeneratedRecipeMeta.self,
                                              options: GenerationOptions(samplingMode: .greedy)).content
            return RecipeMetadata(title: g.title, servings: g.servings, difficulty: g.difficulty, ingredients: g.ingredients)
        } catch {
            throw FoundationModelsErrors.translate(error)
        }
    }
}

/// Maps FoundationModels errors onto `RecipeAnalysisError` so the pipeline stays SDK-agnostic.
nonisolated enum FoundationModelsErrors {
    static func translate(_ error: any Error) -> any Error {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let e = error as? LanguageModelError {
            switch e {
            case .contextSizeExceeded: return RecipeAnalysisError.contextWindowExceeded
            case .guardrailViolation, .refusal: return RecipeAnalysisError.refused(e.localizedDescription)
            default: return e
            }
        }
        return translateLegacy(error)
    }

    /// iOS 26 threw `LanguageModelSession.GenerationError`; it is deprecated on 27 but still the
    /// type older devices produce, so keep mapping it.
    @available(iOS, deprecated: 27.0) @available(macOS, deprecated: 27.0) @available(visionOS, deprecated: 27.0)
    private static func translateLegacy(_ error: any Error) -> any Error {
        guard let e = error as? LanguageModelSession.GenerationError else { return error }
        switch e {
        case .exceededContextWindowSize: return RecipeAnalysisError.contextWindowExceeded
        case .guardrailViolation, .refusal: return RecipeAnalysisError.refused(e.localizedDescription)
        default: return e
        }
    }
}

// MARK: - Routing between on-device, cloud and the demo fallback

/// Picks an analyzer per video: the cloud when on-device isn't available or the video is very
/// long, otherwise on-device; the mock only when nothing else exists. Falls back from cloud to
/// on-device when the network call fails.
///
/// Wire it up with `analyzer: RoutingRecipeAnalyzer.live()` in `CookSession.live()`.
struct RoutingRecipeAnalyzer: RecipeAnalyzer {
    var onDevice: (any RecipeAnalyzer)?
    var cloud: (any RecipeAnalyzer)?
    var fallback: any RecipeAnalyzer = MockRecipeAnalyzer()
    /// Videos longer than this go to the cloud when it is configured.
    var longVideoSeconds: Double = 20 * 60
    /// Transcripts above this many estimated tokens go to the cloud when it is configured.
    var longTranscriptTokens = 6_000

    static func live() -> RoutingRecipeAnalyzer {
        RoutingRecipeAnalyzer(onDevice: OnDeviceRecipeAnalyzer.isAvailable ? OnDeviceRecipeAnalyzer() : nil,
                              cloud: CloudRecipeAnalyzer.fromInfoPlist())
    }

    func isLong(_ transcript: [TranscriptLine], videoDuration: Double) -> Bool {
        videoDuration > longVideoSeconds || TranscriptChunker.estimatedTokens(transcript) > longTranscriptTokens
    }

    func recipe(from transcript: [TranscriptLine], videoDuration: Double) async throws -> Recipe {
        if let cloud, onDevice == nil || isLong(transcript, videoDuration: videoDuration) {
            do {
                return try await cloud.recipe(from: transcript, videoDuration: videoDuration)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard let onDevice else { throw error }
                return try await onDevice.recipe(from: transcript, videoDuration: videoDuration)
            }
        }
        if let onDevice { return try await onDevice.recipe(from: transcript, videoDuration: videoDuration) }
        return try await fallback.recipe(from: transcript, videoDuration: videoDuration)
    }
}

// MARK: - Fallback for machines without Apple Intelligence, and for stage demos

struct MockRecipeAnalyzer: RecipeAnalyzer {
    func recipe(from transcript: [TranscriptLine], videoDuration: Double) async throws -> Recipe {
        try await Task.sleep(for: .seconds(1))
        return .demo
    }
}
