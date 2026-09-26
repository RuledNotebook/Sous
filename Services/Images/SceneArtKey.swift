import Foundation

/// The picture behind a step's scene: which vessel and what is in it ("a pot of boiling water",
/// "an empty frying pan"). Deliberately coarse, so a recipe needs a handful of pictures and every
/// recipe shares them; the ingredients are drawn on top from the bundled Kitchen art.
nonisolated struct SceneArtKey: Hashable, Sendable, Codable {
    enum Contents: String, Sendable, Codable, CaseIterable {
        case empty, water, boilingWater, broth, milk, oil, sizzling, sauce, tray
    }

    var vessel: Vessel
    var contents: Contents

    init(vessel: Vessel, contents: Contents) {
        self.vessel = vessel
        self.contents = contents
    }

    /// Reads the step's words for what the vessel holds at this point.
    init(step: RecipeStep) {
        let vessel = step.sceneVessel
        let text = (step.title + " " + step.instruction).lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        let contents: Contents
        switch vessel {
        case .pot:
            if has("stock", "broth", "soup", "ramen", "curry") { contents = .broth }
            else if has("milk", "cream") { contents = .milk }
            else if has("boil", "simmer", "noodle", "pasta", "spaghetti", "egg", "blanch", "steam") { contents = .boilingWater }
            else if has("water") { contents = .water }
            else { contents = .empty }
        case .pan:
            if has("sear", "fry", "brown", "sizzl", "cook the", "mince", "chicken", "pork", "beef", "shrimp", "bacon") { contents = .sizzling }
            else if has("oil", "butter", "heat", "hot") { contents = .oil }
            else { contents = .empty }
        case .bowl:
            if has("stock", "broth", "soup", "ramen") { contents = .broth }
            else if has("sauce", "dressing", "marinade", "paste", "mix", "combine", "whisk", "stir") { contents = .sauce }
            else if has("water", "rinse", "soak") { contents = .water }
            else { contents = .empty }
        case .oven:
            contents = .tray
        case .board, .plate:
            contents = .empty
        }
        self.init(vessel: vessel, contents: contents)
    }

    /// Cache file name, e.g. "pot-boilingWater".
    var slug: String { "\(vessel.rawValue)-\(contents.rawValue)" }

    /// What the picture shows, in the words the image model gets.
    var subject: String {
        switch (vessel, contents) {
        case (.pot, .empty):        "an empty stainless steel cooking pot"
        case (.pot, .water):        "a stainless steel pot of clear water"
        case (.pot, .boilingWater): "a stainless steel pot of boiling water with a few bubbles and light steam"
        case (.pot, .broth):        "a stainless steel pot of golden broth with light steam"
        case (.pot, .milk):         "a stainless steel pot of creamy white liquid"
        case (.pot, _):             "a stainless steel pot of simmering liquid"
        case (.pan, .empty):        "an empty black frying pan"
        case (.pan, .oil):          "a black frying pan with a thin layer of shimmering oil"
        case (.pan, .sizzling):     "a black frying pan with a little oil and a few sizzle sparks, nothing else in it"
        case (.pan, _):             "a black frying pan with a thin layer of oil"
        case (.bowl, .empty):       "an empty white mixing bowl"
        case (.bowl, .broth):       "a white bowl of golden broth with light steam"
        case (.bowl, .sauce):       "a white mixing bowl with a little dark sauce at the bottom"
        case (.bowl, .water):       "a white bowl of clear water"
        case (.bowl, _):            "an empty white mixing bowl"
        case (.board, _):           "an empty wooden chopping board with a small kitchen knife beside it"
        case (.plate, _):           "an empty white dinner plate"
        case (.oven, _):            "an open oven with an empty baking tray inside"
        }
    }

    /// One prompt shape for every picture, so the set looks like one set.
    var prompt: String {
        "Simple minimal flat vector illustration of \(subject), seen from a slight overhead angle, soft pastel colors, "
        + "clean rounded shapes, centered, nothing else in the frame. Transparent background, no text, no people, no hands."
    }
}
