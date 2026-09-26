import Foundation
import os

/// Errors shared by every analyzer. Model-specific errors are mapped onto these so the pipeline
/// and the UI never depend on a particular SDK.
nonisolated enum RecipeAnalysisError: LocalizedError, Equatable {
    /// The window did not fit the model's context; the pipeline shrinks the window and retries.
    case contextWindowExceeded
    case emptyTranscript
    case noStepsFound
    case modelUnavailable(String)
    case cloudNotConfigured
    case refused(String)
    case badResponse(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .contextWindowExceeded: "The transcript section was too long for the on-device model."
        case .emptyTranscript:       "No narration found. Try a video where the cook talks through the steps."
        case .noStepsFound:          "Couldn't find any cooking steps in this video's narration."
        case .modelUnavailable(let why): "The on-device model isn't available: \(why)"
        case .cloudNotConfigured:    "Add ANTHROPIC_API_KEY to Info.plist to analyze long videos in the cloud."
        case .refused(let why):      "The model declined to analyze this video: \(why)"
        case .badResponse(let why):  "The model returned something unexpected: \(why)"
        case .http(let code, let msg): "The recipe service failed (\(code)): \(msg)"
        }
    }
}

/// What one window of transcript yields.
nonisolated struct ExtractedWindow: Sendable {
    var steps: [StepCandidate]
    var ingredients: [String]
}

/// Anything that can turn one transcript window into steps. Implementations must throw
/// `RecipeAnalysisError.contextWindowExceeded` when the window does not fit their model.
protocol WindowExtractor: Sendable {
    func extract(_ window: TranscriptWindow) async throws -> ExtractedWindow
}

nonisolated struct RecipeMetadata: Sendable, Equatable {
    var title: String
    var servings: Int
    var difficulty: String
    var ingredients: [String]
}

/// Names the dish and cleans up the ingredient list once all steps are known. `videoTitle` is
/// the YouTube title when known: it usually names the dish.
protocol RecipeMetadataProvider: Sendable {
    func metadata(stepTitles: [String], ingredients: [String], videoTitle: String?) async throws -> RecipeMetadata
}

/// Chunked analysis: split the transcript into windows, extract steps per window (shrinking a
/// window and retrying when the model's context overflows), then merge, order, clamp and
/// sanity-check the steps. Everything except the two model calls is deterministic and tested.
struct ChunkedRecipePipeline: Sendable {
    /// Rendered characters per window (~1,100 tokens). Leaves room in the ~4 k context for the
    /// instructions, the schema and up to 8 generated steps; 6 k-character windows still fit.
    var maxWindowCharacters = 4_500
    /// Lines shared by consecutive windows so a boundary step is seen whole at least once.
    var overlapLines = 2
    /// How many times a window may be halved before giving up on it.
    var maxShrinkDepth = 6
    var mergeOptions = StepMerger.Options()
    var grounding = StepGrounding.Options()
    /// Groups small steps into slides when there are more than `StepConsolidation.threshold`.
    var consolidator: (any StepConsolidator)?
    /// The video's title, passed to the metadata pass as a hint for the dish name.
    var videoTitle: String?
    /// Called after each window finishes: (windows done, windows total).
    var progress: (@Sendable (Int, Int) -> Void)?
    /// One line per pipeline stage, for a debug console; the same lines go to the unified log.
    var trace: (@Sendable (String) -> Void)?

    private static let log = Logger(subsystem: "com.cookalong.CookAlong", category: "recipe")

    init() {}

    private func note(_ message: String) {
        Self.log.info("\(message, privacy: .public)")
        trace?(message)
    }

    func run(transcript: [TranscriptLine], videoDuration: Double,
             extractor: any WindowExtractor, metadata: (any RecipeMetadataProvider)?) async throws -> Recipe {
        let lines = transcript.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw RecipeAnalysisError.emptyTranscript }

        let windows = TranscriptChunker.split(lines, maxCharacters: maxWindowCharacters,
                                              overlapLines: overlapLines, videoDuration: videoDuration)
        note("\(lines.count) transcript lines -> \(windows.count) windows")
        var candidates: [StepCandidate] = []
        var ingredients: [String] = []
        var failures: [any Error] = []
        var succeeded = 0

        for (done, window) in windows.enumerated() {
            try Task.checkCancellation()
            do {
                for extracted in try await extract(window, extractor: extractor, depth: 0) {
                    candidates += extracted.steps
                    ingredients += extracted.ingredients
                }
                succeeded += 1
                note("window \(done + 1)/\(windows.count) [\(Int(window.startSecond))s-\(Int(window.endSecond))s]: \(candidates.count) candidates so far")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One bad window (a guardrail trip on "kill the heat", say) shouldn't sink the recipe.
                failures.append(error)
                note("window \(done + 1)/\(windows.count) failed: \(error.localizedDescription)")
            }
            progress?(done + 1, windows.count)
        }
        if succeeded == 0, let first = failures.first { throw first }

        let deduped = StepMerger.merge(candidates, options: mergeOptions)
        let merged = deduped.filter { !ChatterFilter.isChatter(title: $0.title, instruction: $0.instruction) }
        note("\(candidates.count) candidates -> \(deduped.count) after merge -> \(merged.count) after chatter filter")
        guard !merged.isEmpty else { throw RecipeAnalysisError.noStepsFound }
        var steps = Self.finalize(merged, videoDuration: videoDuration)
        if let consolidator, steps.count > StepConsolidation.threshold {
            do {
                let plan = try await consolidator.plan(for: steps)
                if let slides = StepConsolidation.apply(plan, to: steps) {
                    note("consolidated \(steps.count) steps into \(slides.count) slides")
                    steps = slides
                } else {
                    note("consolidation plan rejected (\(plan.slides.count) slides for \(steps.count) steps); keeping steps")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                note("consolidation failed: \(error.localizedDescription)")
            }
        }
        let allIngredients = Self.dedupeIngredients(ingredients)

        var meta = RecipeMetadata(title: "Recipe from video", servings: 4, difficulty: Self.difficulty(for: steps),
                                  ingredients: allIngredients)
        if let metadata {
            do {
                let m = try await metadata.metadata(stepTitles: steps.map(\.title), ingredients: allIngredients, videoTitle: videoTitle)
                meta.title = m.title.isEmpty ? meta.title : m.title
                meta.servings = (1...12).contains(m.servings) ? m.servings : meta.servings
                meta.difficulty = ["easy", "medium", "hard"].contains(m.difficulty) ? m.difficulty : meta.difficulty
                meta.ingredients = m.ingredients.isEmpty ? allIngredients : Self.dedupeIngredients(m.ingredients)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep the steps; the fallback metadata is good enough to cook from.
            }
        }
        return Recipe(title: meta.title, servings: meta.servings, difficulty: meta.difficulty,
                      ingredients: meta.ingredients, steps: steps)
    }

    /// Extracts one window, halving it and recursing when the model reports a context overflow.
    private func extract(_ window: TranscriptWindow, extractor: any WindowExtractor, depth: Int) async throws -> [ExtractedWindow] {
        do {
            let extracted = try await extractor.extract(window)
            let grounded = StepGrounding.ground(Self.tag(extracted.steps, with: window), in: window.lines, options: grounding)
            if grounded.count < extracted.steps.count {
                note("dropped \(extracted.steps.count - grounded.count) ungrounded step(s) in [\(Int(window.startSecond))s-\(Int(window.endSecond))s]")
            }
            return [ExtractedWindow(steps: grounded, ingredients: extracted.ingredients)]
        } catch RecipeAnalysisError.contextWindowExceeded {
            let halves = TranscriptChunker.halve(window)
            guard halves.count == 2, depth < maxShrinkDepth else { throw RecipeAnalysisError.contextWindowExceeded }
            var out: [ExtractedWindow] = []
            for half in halves {
                out += try await extract(half, extractor: extractor, depth: depth + 1)
            }
            return out
        }
    }

    /// Stamps provenance on each candidate and keeps its start inside the window it came from.
    static func tag(_ steps: [StepCandidate], with window: TranscriptWindow) -> [StepCandidate] {
        let lower = window.startSecond
        let upper = max(window.endSecond, lower)
        return steps.enumerated().map { order, step in
            var s = step
            s.windowIndex = window.index
            s.windowStart = lower
            s.windowEnd = upper
            s.order = order
            s.startSecond = min(max(step.startSecond, lower), upper)
            return s
        }
    }

    /// Minutes sanity, timer flags and timestamp clamping. Shared with the cloud analyzer.
    static func finalize(_ merged: [StepCandidate], videoDuration: Double) -> [RecipeStep] {
        let starts = TimestampClamper.clamp(merged.map(\.startSecond), videoDuration: videoDuration)
        return zip(merged, starts).map { s, start in
            let minutes = MinutesEstimator.minutes(model: s.minutes, title: s.title, instruction: s.instruction, isHandsOn: s.isHandsOn)
            let needsTimer = MinutesEstimator.needsTimer(model: s.needsTimer, title: s.title, instruction: s.instruction)
            return RecipeStep(title: capitalized(s.title.trimmingCharacters(in: .whitespacesAndNewlines)),
                              instruction: s.instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                              startSecond: Int(start.rounded()), minutes: minutes, isHandsOn: s.isHandsOn,
                              needsTimer: needsTimer, tip: s.tip, imagePrompt: s.imagePrompt,
                              vessel: Vessel(rawValue: s.vessel), items: s.items.isEmpty ? nil : s.items)
        }
    }

    /// "boil pasta" -> "Boil pasta". Small models are inconsistent about this.
    nonisolated static func capitalized(_ title: String) -> String {
        guard let first = title.first else { return title }
        return first.uppercased() + title.dropFirst()
    }

    /// Case-insensitive dedupe that prefers the more specific mention ("4 garlic cloves" over "garlic").
    static func dedupeIngredients(_ raw: [String]) -> [String] {
        var out: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let words = StepMerger.contentWords(trimmed)
            guard !words.isEmpty else { continue }
            if let i = out.firstIndex(where: { existing in
                let ew = StepMerger.contentWords(existing)
                return ew == words || ew.isSubset(of: words) || words.isSubset(of: ew)
            }) {
                if trimmed.count > out[i].count { out[i] = trimmed }
            } else {
                out.append(trimmed)
            }
        }
        return out
    }

    static func difficulty(for steps: [RecipeStep]) -> String {
        let handsOn = steps.filter(\.isHandsOn).reduce(0) { $0 + $1.minutes }
        switch (steps.count, handsOn) {
        case (..<7, ..<25): return "easy"
        case (..<13, ..<60): return "medium"
        default: return "hard"
        }
    }
}
