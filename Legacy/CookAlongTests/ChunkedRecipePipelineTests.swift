import Testing
@testable import CookAlong

/// Extracts steps by keyword so the pipeline can be exercised end to end without a model.
/// Throws the context-overflow error for windows above `overflowAbove` characters.
@MainActor
final class KeywordExtractor: WindowExtractor {
    let overflowAbove: Int
    private(set) var calls: [TranscriptWindow] = []
    private(set) var overflows = 0
    var failWindowsContaining: String?

    init(overflowAbove: Int = .max) { self.overflowAbove = overflowAbove }

    static let rules: [(keyword: String, title: String, minutes: Int, handsOn: Bool)] = [
        ("pot of water", "Boil the water", 1, false),
        ("pat the shrimp", "Pat the shrimp dry", 2, true),
        ("now the garlic", "Slice the garlic", 3, true),
        ("parsley, roughly", "Chop the parsley", 2, true),
        ("spaghetti goes in", "Cook the pasta", 1, false),
        ("pan on medium", "Heat the pan", 2, true),
        ("shrimp in", "Sear the shrimp", 1, true),
        ("rest of the butter", "Make the garlic butter", 2, true),
        ("straight into the pan", "Toss the pasta", 2, true),
        ("shrimp back in", "Add shrimp and parsley", 1, true),
        ("plate it up", "Plate and serve", 1, true),
        ("oven on", "Preheat the oven", 1, false),
        ("salmon on a tray", "Season the salmon", 3, true),
        ("into the oven for", "Bake the salmon", 1, false),
        ("rest for five", "Rest the salmon", 1, false),
        ("serve with", "Serve", 1, true),
    ]

    func extract(_ window: TranscriptWindow) async throws -> ExtractedWindow {
        calls.append(window)
        if window.characterCount > overflowAbove {
            overflows += 1
            throw RecipeAnalysisError.contextWindowExceeded
        }
        if let bad = failWindowsContaining, window.rendered.contains(bad) {
            throw RecipeAnalysisError.refused("guardrail")
        }
        var steps: [StepCandidate] = []
        var ingredients: [String] = []
        for line in window.lines {
            let text = line.text.lowercased()
            for rule in Self.rules where text.contains(rule.keyword) {
                steps.append(StepCandidate(title: rule.title, instruction: line.text, startSecond: line.start,
                                           minutes: rule.minutes, isHandsOn: rule.handsOn, needsTimer: false))
            }
            if text.contains("grams of spaghetti") { ingredients += ["200 g spaghetti", "shrimp", "garlic"] }
            if text.contains("now the garlic") { ingredients.append("4 cloves garlic") }
        }
        return ExtractedWindow(steps: steps, ingredients: ingredients)
    }
}

@MainActor
struct FixedMetadata: RecipeMetadataProvider {
    var title = "Garlic butter shrimp pasta"
    var fail = false
    func metadata(stepTitles: [String], ingredients: [String]) async throws -> RecipeMetadata {
        if fail { throw RecipeAnalysisError.badResponse("nope") }
        return RecipeMetadata(title: title, servings: 2, difficulty: "easy", ingredients: ingredients)
    }
}

@MainActor
struct ChunkedRecipePipelineTests {
    let transcript = SampleTranscripts.shrimpPasta
    let duration = 190.0

    @Test func shortTranscriptGivesOrderedStepsWithClampedTimestamps() async throws {
        let extractor = KeywordExtractor()
        let recipe = try await ChunkedRecipePipeline().run(transcript: transcript, videoDuration: duration,
                                                            extractor: extractor, metadata: FixedMetadata())
        #expect(extractor.calls.count == 1)
        #expect(recipe.title == "Garlic butter shrimp pasta")
        #expect(recipe.steps.map(\.title) == [
            "Boil the water", "Pat the shrimp dry", "Slice the garlic", "Chop the parsley", "Cook the pasta",
            "Heat the pan", "Sear the shrimp", "Make the garlic butter", "Toss the pasta",
            "Add shrimp and parsley", "Plate and serve",
        ])
        let starts = recipe.steps.map(\.videoStart)
        #expect(starts == starts.sorted())
        #expect(starts.allSatisfy { $0 >= 0 && $0 < duration })
        #expect(zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 })
        // Merged ingredient list prefers the specific mention.
        #expect(recipe.ingredients.contains("4 cloves garlic"))
        #expect(!recipe.ingredients.contains("garlic"))
    }

    @Test func minutesAreRealisticAfterFinalize() async throws {
        let recipe = try await ChunkedRecipePipeline().run(transcript: transcript, videoDuration: duration,
                                                            extractor: KeywordExtractor(), metadata: nil)
        let byTitle = Dictionary(uniqueKeysWithValues: recipe.steps.map { ($0.title, $0) })
        #expect(byTitle["Cook the pasta"]?.minutes == 10)          // "one minute less ... about nine minutes" -> 1 + 9
        #expect(byTitle["Cook the pasta"]?.needsTimer == true)
        #expect(byTitle["Sear the shrimp"]?.minutes == 2)          // "one minute per side"
        #expect(byTitle["Make the garlic butter"]?.minutes == 2)   // "rest of the butter" is not a rest
        #expect((byTitle["Boil the water"]?.minutes ?? 0) >= 8)     // passive floor, model said 1
        #expect(recipe.totalMinutes >= 30)
    }

    @Test func longTranscriptIsChunkedAndDuplicatesFromOverlapAreMerged() async throws {
        let long = SampleTranscripts.long(minutes: 45)
        var pipeline = ChunkedRecipePipeline()
        pipeline.maxWindowCharacters = 1_500
        let extractor = KeywordExtractor()
        let recipe = try await pipeline.run(transcript: long, videoDuration: 45 * 60, extractor: extractor, metadata: nil)

        #expect(extractor.calls.count > 5)
        // Every window fit the budget, so nothing needed shrinking.
        #expect(extractor.overflows == 0)

        // The raw candidates contain duplicates (overlap lines are extracted twice); the recipe does not.
        let raw = extractor.calls.flatMap(\.lines).count
        #expect(raw > long.count)
        let keyed = recipe.steps.map { "\($0.title)@\(Int($0.videoStart))" }
        #expect(Set(keyed).count == keyed.count)

        // Same number of steps per repeated block as the single-block recipe (11), in order.
        let blocks = Int(45 * 60 / 200)   // whole 200 s blocks that fit in the video
        #expect(recipe.steps.count == 11 * blocks)
        let starts = recipe.steps.map(\.videoStart)
        #expect(zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 })
        #expect(starts.last! < 45 * 60)
    }

    @Test func contextOverflowShrinksTheWindowAndRetries() async throws {
        var pipeline = ChunkedRecipePipeline()
        pipeline.maxWindowCharacters = 2_000            // the chunker thinks this fits...
        let extractor = KeywordExtractor(overflowAbove: 700)   // ...but the "model" only takes 700 chars
        let recipe = try await pipeline.run(transcript: transcript, videoDuration: duration, extractor: extractor, metadata: nil)

        #expect(extractor.overflows >= 1)
        #expect(extractor.calls.count > extractor.overflows)
        // Every successful call was within the model's real limit.
        let successes = extractor.calls.filter { $0.characterCount <= 700 }
        #expect(successes.count == extractor.calls.count - extractor.overflows)
        // Halved windows still cover the whole transcript: nothing lost.
        #expect(recipe.steps.count == 11)
        #expect(recipe.steps.first?.title == "Boil the water")
        #expect(recipe.steps.last?.title == "Plate and serve")
    }

    @Test func givesUpWhenASingleWordStillOverflows() async {
        let extractor = KeywordExtractor(overflowAbove: 3)
        await #expect(throws: RecipeAnalysisError.contextWindowExceeded) {
            try await ChunkedRecipePipeline().run(transcript: [TranscriptLine(start: 0, text: "stir")],
                                                  videoDuration: 5, extractor: extractor, metadata: nil)
        }
    }

    @Test func oneBadWindowDoesNotSinkTheRecipe() async throws {
        var pipeline = ChunkedRecipePipeline()
        pipeline.maxWindowCharacters = 500
        let extractor = KeywordExtractor()
        extractor.failWindowsContaining = "Look at that colour"
        let recipe = try await pipeline.run(transcript: transcript, videoDuration: duration, extractor: extractor, metadata: nil)
        #expect(recipe.steps.count >= 6)
        #expect(recipe.steps.first?.title == "Boil the water")
    }

    @Test func allWindowsFailingSurfacesTheError() async {
        let extractor = KeywordExtractor()
        extractor.failWindowsContaining = "["   // every rendered line has a timestamp
        await #expect(throws: RecipeAnalysisError.refused("guardrail")) {
            try await ChunkedRecipePipeline().run(transcript: transcript, videoDuration: duration, extractor: extractor, metadata: nil)
        }
    }

    @Test func metadataFailureFallsBackToDefaults() async throws {
        let recipe = try await ChunkedRecipePipeline().run(transcript: transcript, videoDuration: duration,
                                                            extractor: KeywordExtractor(), metadata: FixedMetadata(fail: true))
        #expect(recipe.title == "Recipe from video")
        #expect(recipe.servings == 4)
        #expect(["easy", "medium", "hard"].contains(recipe.difficulty))
        #expect(recipe.steps.count == 11)
    }

    @Test func emptyTranscriptAndNoStepsAreDistinctErrors() async {
        await #expect(throws: RecipeAnalysisError.emptyTranscript) {
            try await ChunkedRecipePipeline().run(transcript: [], videoDuration: 10, extractor: KeywordExtractor(), metadata: nil)
        }
        await #expect(throws: RecipeAnalysisError.noStepsFound) {
            try await ChunkedRecipePipeline().run(transcript: [TranscriptLine(start: 0, text: "Hello and welcome.")],
                                                  videoDuration: 10, extractor: KeywordExtractor(), metadata: nil)
        }
    }

    @Test func jumpCutBakeGetsRealMinutes() async throws {
        let recipe = try await ChunkedRecipePipeline().run(transcript: SampleTranscripts.bakedSalmon, videoDuration: 66,
                                                            extractor: KeywordExtractor(), metadata: nil)
        let bake = try #require(recipe.steps.first { $0.title == "Bake the salmon" })
        #expect(bake.minutes == 25)
        #expect(bake.needsTimer)
        #expect(bake.videoStart == 40)
        let rest = try #require(recipe.steps.first { $0.title == "Rest the salmon" })
        #expect(rest.minutes == 5)
    }
}
