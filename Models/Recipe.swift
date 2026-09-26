import Foundation

/// UI-facing model. The recipe session maps whatever it gets from YouTube into this;
/// nothing here depends on how the recipe was made.
nonisolated struct Recipe: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var title: String
    var servings: Int
    var difficulty: String              // "easy" | "medium" | "hard"
    var ingredients: [String]
    var steps: [RecipeStep]
    var sourceURL: URL?                 // the YouTube link the recipe came from
    var thumbnailURL: URL?              // video thumbnail, shown on the ingredients slide
    var channel: String?                // the YouTube channel, if known
    var ingredientEvidence: [IngredientEvidence]?   // where each ingredient was said; see IngredientGrounding

    var totalMinutes: Int   { steps.reduce(0) { $0 + $1.minutes } }
    var handsOnMinutes: Int { steps.filter(\.isHandsOn).reduce(0) { $0 + $1.minutes } }

    /// Minutes remaining counting the step at `index` and everything after it.
    func minutesLeft(from index: Int) -> Int {
        guard steps.indices.contains(index) else { return 0 }
        return steps[index...].reduce(0) { $0 + $1.minutes }
    }

    /// YouTube video ID parsed from `sourceURL`, if it is a YouTube link.
    var videoID: String? { sourceURL.flatMap { try? YouTubeLink.videoID(from: $0.absoluteString) } }

    /// youtube.com/watch?v=ID&t=Ns for the moment this step begins in the video.
    func watchURL(for step: RecipeStep) -> URL? {
        guard let videoID,
              var components = URLComponents(url: YouTubeLink.watchURL(for: videoID), resolvingAgainstBaseURL: false)
        else { return nil }
        if step.startSecond > 0 {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: "\(step.startSecond)s")]
        }
        return components.url
    }
}

nonisolated struct RecipeStep: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var title: String
    var instruction: String
    var startSecond: Int        // where this step begins in the video
    var minutes: Int            // real kitchen time, not video time
    var isHandsOn: Bool         // chopping/stirring vs. waiting (simmer, bake, rest)
    var needsTimer: Bool
    var tip: String
    var imagePrompt: String     // fed to the image generator
    var vessel: Vessel?         // where the step happens, if the model said; see RecipeStep.sceneVessel
    var items: [String]?        // Kitchen asset names the model picked; see RecipeStep.sceneItems
}

/// One ingredient and the transcript words that back it up. `found` is nil until the words
/// have been checked against the transcript (see `IngredientGrounding`).
nonisolated struct IngredientEvidence: Hashable, Codable, Sendable {
    var name: String
    var amount: String
    var evidence: String
    var second: Int
    var found: Bool?

    /// "6 tbsp soy sauce", or just the name when no amount was said.
    var label: String {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : "\(trimmed) \(name)"
    }
}

/// Where a step happens. Drawn large in the middle of the step slide.
nonisolated enum Vessel: String, Codable, Sendable, CaseIterable {
    case pot, pan, bowl, board, oven, plate
}

// MARK: - Demo data (reliable on stage, no model/network needed)

extension Recipe {
    /// The video ID below is a placeholder: swap in the real clip's ID and match `startSecond`s to it.
    static let demoVideoID = "Y7r6Ah0LQfA"

    static let demo = Recipe(
        title: "Garlic butter shrimp pasta",
        servings: 2,
        difficulty: "easy",
        ingredients: ["200 g spaghetti", "250 g shrimp, peeled", "4 garlic cloves, sliced",
                      "3 tbsp butter", "1 lemon", "Chili flakes", "A handful of parsley", "Salt"],
        steps: [
            .init(title: "Boil the water", instruction: "Bring a large pot of well-salted water to a rolling boil.",
                  startSecond: 0, minutes: 8, isHandsOn: false, needsTimer: false,
                  tip: "It should taste like the sea.", imagePrompt: "large pot of boiling water on a stove"),
            .init(title: "Prep garlic and parsley", instruction: "Thinly slice the garlic and roughly chop a handful of parsley.",
                  startSecond: 15, minutes: 4, isHandsOn: true, needsTimer: false,
                  tip: "Thin slices turn golden evenly.", imagePrompt: "sliced garlic and chopped parsley on a cutting board"),
            .init(title: "Cook the pasta", instruction: "Add spaghetti and cook 1 minute less than the packet says. Save a mug of pasta water.",
                  startSecond: 40, minutes: 9, isHandsOn: false, needsTimer: true,
                  tip: "The pasta finishes in the pan.", imagePrompt: "spaghetti cooking in a pot"),
            .init(title: "Sear the shrimp", instruction: "Melt 1 tbsp butter over medium-high heat. Sear shrimp 1 minute per side, then set aside.",
                  startSecond: 75, minutes: 3, isHandsOn: true, needsTimer: true,
                  tip: "Pat them dry first so they brown.", imagePrompt: "shrimp searing in a skillet with butter"),
            .init(title: "Make the garlic butter", instruction: "Lower the heat, add the remaining butter, garlic and chili. Cook until fragrant and pale gold.",
                  startSecond: 110, minutes: 2, isHandsOn: true, needsTimer: false,
                  tip: "Pull it before the garlic browns.", imagePrompt: "garlic sizzling in melted butter"),
            .init(title: "Toss everything", instruction: "Add pasta, a splash of pasta water and lemon juice. Toss until glossy, then return the shrimp.",
                  startSecond: 150, minutes: 2, isHandsOn: true, needsTimer: false,
                  tip: "More water if it looks tight.", imagePrompt: "glossy spaghetti being tossed in a pan with shrimp"),
            .init(title: "Plate and serve", instruction: "Finish with parsley and lemon zest. Serve right away.",
                  startSecond: 190, minutes: 1, isHandsOn: true, needsTimer: false,
                  tip: "", imagePrompt: "plated garlic butter shrimp spaghetti with parsley"),
        ],
        sourceURL: YouTubeLink.watchURL(for: demoVideoID),
        thumbnailURL: YouTubeLink.thumbnailURL(for: demoVideoID),
        channel: "Sous demo"
    )
}
