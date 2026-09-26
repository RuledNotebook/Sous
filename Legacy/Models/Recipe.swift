import Foundation

/// UI-facing model. Kept separate from the @Generable types so the UI
/// never depends on FoundationModels (and the mock/demo path stays trivial).
struct Recipe: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var servings: Int
    var difficulty: String
    var ingredients: [String]
    var steps: [RecipeStep]

    var totalMinutes: Int   { steps.reduce(0) { $0 + $1.minutes } }
    var handsOnMinutes: Int { steps.filter(\.isHandsOn).reduce(0) { $0 + $1.minutes } }

    /// Minutes remaining counting the step at `index` and everything after it.
    func minutesLeft(from index: Int) -> Int {
        guard steps.indices.contains(index) else { return 0 }
        return steps[index...].reduce(0) { $0 + $1.minutes }
    }

    /// Which step the video is in at a given playback time.
    func stepIndex(at seconds: Double) -> Int {
        steps.lastIndex { $0.videoStart <= seconds + 0.05 } ?? 0
    }
}

struct RecipeStep: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var instruction: String
    var videoStart: Double      // seconds into the video where this step begins
    var minutes: Int            // real-world time the step takes (not video time)
    var isHandsOn: Bool         // chopping/stirring vs. waiting (simmer, bake, rest)
    var needsTimer: Bool
    var tip: String
    var imagePrompt: String     // fed to the image generator
}

// MARK: - Demo data (reliable on stage, no model/network needed)
// Match these videoStart values to whatever demo.mp4 you bundle.
extension Recipe {
    static let demo = Recipe(
        title: "Garlic butter shrimp pasta",
        servings: 2,
        difficulty: "easy",
        ingredients: ["200 g spaghetti", "250 g shrimp, peeled", "4 garlic cloves, sliced",
                      "3 tbsp butter", "1 lemon", "Chili flakes", "Parsley", "Salt"],
        steps: [
            .init(title: "Boil the water", instruction: "Bring a large pot of well-salted water to a rolling boil.",
                  videoStart: 0, minutes: 8, isHandsOn: false, needsTimer: false,
                  tip: "It should taste like the sea.", imagePrompt: "large pot of boiling water on a stove"),
            .init(title: "Prep garlic and parsley", instruction: "Thinly slice the garlic and roughly chop a handful of parsley.",
                  videoStart: 15, minutes: 4, isHandsOn: true, needsTimer: false,
                  tip: "Thin slices turn golden evenly.", imagePrompt: "sliced garlic and chopped parsley on a cutting board"),
            .init(title: "Cook the pasta", instruction: "Add spaghetti and cook 1 minute less than the packet says. Save a mug of pasta water.",
                  videoStart: 40, minutes: 9, isHandsOn: false, needsTimer: true,
                  tip: "The pasta finishes in the pan.", imagePrompt: "spaghetti cooking in a pot"),
            .init(title: "Sear the shrimp", instruction: "Melt 1 tbsp butter over medium-high heat. Sear shrimp 1 minute per side, then set aside.",
                  videoStart: 75, minutes: 3, isHandsOn: true, needsTimer: true,
                  tip: "Pat them dry first so they brown.", imagePrompt: "shrimp searing in a skillet with butter"),
            .init(title: "Make the garlic butter", instruction: "Lower the heat, add remaining butter, garlic and chili. Cook until fragrant and pale gold.",
                  videoStart: 110, minutes: 2, isHandsOn: true, needsTimer: false,
                  tip: "Pull it before the garlic browns.", imagePrompt: "garlic sizzling in melted butter"),
            .init(title: "Toss everything", instruction: "Add pasta, a splash of pasta water and lemon juice. Toss until glossy, then return the shrimp.",
                  videoStart: 150, minutes: 2, isHandsOn: true, needsTimer: false,
                  tip: "More water if it looks tight.", imagePrompt: "glossy spaghetti being tossed in a pan with shrimp"),
            .init(title: "Plate and serve", instruction: "Finish with parsley and lemon zest. Serve right away.",
                  videoStart: 190, minutes: 1, isHandsOn: true, needsTimer: false,
                  tip: "", imagePrompt: "plated garlic butter shrimp spaghetti with parsley"),
        ]
    )
}
