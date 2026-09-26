import Foundation
import Testing
@testable import CookAlong

@MainActor
struct StepNeedsTests {
    private func step(_ instruction: String, title: String = "Do it", items: [String]? = nil) -> RecipeStep {
        RecipeStep(title: title, instruction: instruction, startSecond: 0, minutes: 2, isHandsOn: true, needsTimer: false,
                   tip: "", imagePrompt: "", vessel: nil, items: items)
    }

    @Test func readsAmountsFromTheSentence() {
        let q = StepNeeds.quantities(in: "Combine 1 cup water, 6 tbsp soy sauce, 3 tsp brown sugar, 2 tablespoons cornstarch, and ground black pepper.")
        #expect(q.map(\.amount) == ["1 cup", "6 tbsp", "3 tsp", "2 tbsp"])
        #expect(q.map(\.item) == ["water", "soy sauce", "brown sugar", "cornstarch"])
    }

    @Test func handlesFractionsCountsAndPhrases() {
        let q = StepNeeds.quantities(in: "Add 1/2 cup teriyaki sauce, 3 chicken breasts, 2 eggs, a pinch of salt and a splash of vinegar to the pan.")
        #expect(q.map(\.amount) == ["1/2 cup", "3", "2", "a pinch of", "a splash of"])
        #expect(q.map(\.item) == ["teriyaki sauce", "chicken breasts", "eggs", "salt", "vinegar"])
    }

    @Test func ignoresTimesAndVagueCounts() {
        #expect(StepNeeds.quantities(in: "Bake for 25 minutes at 200 degrees, then rest 5 minutes.").isEmpty)
        #expect(StepNeeds.quantities(in: "Give it a nice colour on one side.").isEmpty)
        #expect(StepNeeds.quantities(in: "Take a little care with the eggs.").isEmpty)
    }

    @Test func needsCombineAmountsWithSceneItems() {
        let s = step("Stir in 2 tbsp gochujang and some soy sauce over the cooked chicken.", items: ["garlic", "ginger_root", "soy"])
        let needs = StepNeeds.needs(for: s)
        #expect(needs.first == StepNeed(label: "gochujang", amount: "2 tbsp", asset: KitchenAssets.asset(for: "gochujang")))
        #expect(needs.map(\.label).contains("garlic"))
        #expect(needs.count <= StepNeeds.maxNeeds)
        // No duplicates by asset.
        let assets = needs.compactMap(\.asset)
        #expect(Set(assets).count == assets.count)
    }

    @Test func fallsBackToTheSceneWhenNothingIsMeasured() {
        let s = step("Slice the garlic thinly and grate the ginger.")
        let labels = StepNeeds.needs(for: s).map(\.label)
        #expect(labels.contains("garlic") && labels.contains("ginger"))
        #expect(StepNeeds.needs(for: s).allSatisfy { $0.amount == nil })
    }

    @Test func assetsGetKitchenNames() {
        #expect(StepNeeds.displayName(for: "droplet") == "water")
        #expect(StepNeeds.displayName(for: "cut_of_meat") == "meat")
        #expect(StepNeeds.displayName(for: "bok_choy") == "bok choy")
        let s = step("Add spaghetti to the boiling water.", items: ["spaghetti", "droplet"])
        #expect(StepNeeds.needs(for: s).map(\.label) == ["spaghetti", "water"])
    }
}

struct SceneArtKeyTests {
    private func step(_ title: String, _ instruction: String, vessel: Vessel? = nil) -> RecipeStep {
        RecipeStep(title: title, instruction: instruction, startSecond: 0, minutes: 1, isHandsOn: true, needsTimer: false,
                   tip: "", imagePrompt: "", vessel: vessel, items: nil)
    }

    @Test func readsWhatTheVesselHolds() {
        #expect(SceneArtKey(step: step("Boil eggs", "Put eggs in the boiling water.", vessel: .pot)).contents == .boilingWater)
        #expect(SceneArtKey(step: step("Heat chicken stock", "Heat chicken stock cubes with hot water.", vessel: .pot)).contents == .broth)
        #expect(SceneArtKey(step: step("Heat the wok", "Bring the wok to a high temperature with a little oil.", vessel: .pan)).contents == .oil)
        #expect(SceneArtKey(step: step("Sear chicken mince", "Sear the chicken mince on one side.", vessel: .pan)).contents == .sizzling)
        #expect(SceneArtKey(step: step("Mix seasoning", "Combine chili oil, vinegar and soy sauce in a bowl.", vessel: .bowl)).contents == .sauce)
        #expect(SceneArtKey(step: step("Grate ginger", "Grate the ginger.", vessel: .board)).contents == .empty)
        #expect(SceneArtKey(step: step("Bake", "Bake for 20 minutes.", vessel: .oven)).contents == .tray)
        #expect(SceneArtKey(step: step("Put water on", "Put a pot of water on.")).vessel == .pot)
    }

    @Test func promptsAndSlugsAreStable() {
        let key = SceneArtKey(vessel: .pot, contents: .boilingWater)
        #expect(key.slug == "pot-boilingWater")
        #expect(key.prompt.contains("boiling water"))
        #expect(key.prompt.contains("Transparent background"))
        #expect(SceneArtKey(vessel: .plate, contents: .broth).subject == "an empty white dinner plate")
    }
}
