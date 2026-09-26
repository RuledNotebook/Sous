import Foundation
import Testing
@testable import CookAlong

@MainActor
struct IngredientGroundingTests {
    let transcript: [TranscriptLine] = [
        .init(start: 51, text: "We need to boil eggs, noodles, and some vegetable here."),
        .init(start: 58, text: "So I'm going to put my eggs in here."),
        .init(start: 140, text: "I'm using six tablespoons of soy sauce,"),
        .init(start: 144, text: "three teaspoons of brown sugar and two tablespoons of cornstarch."),
        .init(start: 480, text: "Some gochujang for that spicy, smoky flavour."),
    ]

    private func claim(_ name: String, _ amount: String = "", _ evidence: String, second: Int = 0) -> IngredientEvidence {
        IngredientEvidence(name: name, amount: amount, evidence: evidence, second: second, found: nil)
    }

    @Test func normalizesCaseAndPunctuation() {
        #expect(IngredientGrounding.normalize("  Six Tablespoons of SOY sauce, please!  ") == "six tablespoons of soy sauce please")
        #expect(IngredientGrounding.normalize("I'm") == "i m")
    }

    @Test func keepsIngredientsWhoseWordsAreInTheTranscript() {
        let rows = IngredientGrounding.verify([
            claim("soy sauce", "6 tbsp", "six tablespoons of soy sauce", second: 140),
            claim("eggs", "", "boil eggs", second: 51),
        ], transcript: transcript)
        #expect(rows.map(\.found) == [true, true])
        #expect(IngredientGrounding.kept(rows) == ["6 tbsp soy sauce", "eggs"])
    }

    @Test func dropsIngredientsWithMadeUpEvidence() {
        let rows = IngredientGrounding.verify([
            claim("sesame oil", "1 tbsp", "a tablespoon of sesame oil"),   // never said
            claim("kimchi", "", ""),                                        // no evidence at all
            claim("tangerine", "", "a tangerine"),
        ], transcript: transcript)
        #expect(rows.map(\.found) == [false, false, false])
        #expect(IngredientGrounding.kept(rows).isEmpty)
    }

    @Test func evidenceMayStraddleALineBreakAndSnapsTheTimestamp() {
        let rows = IngredientGrounding.verify([
            claim("brown sugar", "3 tsp", "soy sauce, three teaspoons of brown sugar", second: 999),
        ], transcript: transcript)
        #expect(rows[0].found == true)
        #expect(rows[0].second == 140)   // the line the words start on
    }

    @Test func wordBoundariesMatter() {
        // "egg" alone is not "eggs"... but "eggs" is said, so the claim must quote it.
        let rows = IngredientGrounding.verify([claim("egg", "", "eg")], transcript: transcript)
        #expect(rows[0].found == false)
    }

    @Test func duplicateNamesCollapseOntoTheFirst() {
        let rows = IngredientGrounding.verify([
            claim("Soy sauce", "6 tbsp", "six tablespoons of soy sauce"),
            claim("soy sauce", "", "soy sauce"),
        ], transcript: transcript)
        #expect(rows.count == 1)
        #expect(rows[0].amount == "6 tbsp")
    }

    @Test func printsATable() {
        let rows = IngredientGrounding.verify([
            claim("soy sauce", "6 tbsp", "six tablespoons of soy sauce"),
            claim("sesame oil", "", "sesame oil"),
        ], transcript: transcript)
        let table = IngredientGrounding.table(rows)
        #expect(table.contains("ingredient"))
        #expect(table.contains("6 tbsp soy sauce"))
        #expect(table.contains("| yes"))
        #expect(table.contains("| no"))
        #expect(table.hasSuffix("1 of 2 ingredients found in the transcript"))
    }

    @Test func modelReportSaysHowMuchWasSent() {
        let full = ModelReport(model: "OpenAI gpt-5-mini", transcriptLines: 218, transcriptCharacters: 14_000, sentCharacters: 14_000)
        #expect(full.description == "model: OpenAI gpt-5-mini | transcript: 218 lines, 14000 chars | sent: 14000 chars (100%)")
        let thin = ModelReport(model: "x", transcriptLines: 10, transcriptCharacters: 1_000, sentCharacters: 500)
        #expect(thin.isThinned && thin.description.hasSuffix("(50%) THINNED"))
    }

    @Test func payloadAcceptsObjectsAndPlainStrings() throws {
        let json = """
        {"title":"Ramen","servings":2,"difficulty":"easy","ingredients":[
          {"name":"soy sauce","amount":"6 tbsp","evidence":"six tablespoons of soy sauce","second":140},
          "2 eggs"],
         "steps":[{"title":"Boil eggs","instruction":"Boil the eggs.","startSecond":58,"minutes":8,"isHandsOn":false,"needsTimer":true,"tip":"","imagePrompt":""}]}
        """
        let payload = try JSONDecoder().decode(GroundedRecipePayload.self, from: Data(json.utf8))
        let recipe = payload.recipe(videoDuration: 900)
        #expect(recipe.ingredients == ["6 tbsp soy sauce", "2 eggs"])
        #expect(recipe.ingredientEvidence?.map(\.evidence) == ["six tablespoons of soy sauce", ""])
        #expect(recipe.ingredientEvidence?.allSatisfy { $0.found == nil } == true)

        let grounded = RecipeGrounding.ground(recipe, transcript: transcript)
        #expect(grounded.recipe.ingredients == ["6 tbsp soy sauce"])          // the bare string has no evidence
        #expect(grounded.recipe.ingredientEvidence?.map(\.found) == [true, false])
        #expect(grounded.table.contains("2 eggs"))
    }
}

@MainActor
struct StepItemGroundingTests {
    let transcript: [TranscriptLine] = [
        .init(start: 51, text: "We need to boil eggs, noodles, and some vegetable here."),
        .init(start: 58, text: "So I'm going to put my eggs in here and swirl the water."),
        .init(start: 400, text: "Get the wok heating up, then the chicken mince goes in."),
    ]

    private func step(_ title: String, _ instruction: String, at second: Int, items: [String]?) -> RecipeStep {
        RecipeStep(title: title, instruction: instruction, startSecond: second, minutes: 5, isHandsOn: true, needsTimer: false,
                   tip: "", imagePrompt: "a bowl of tangerines", vessel: nil, items: items)
    }

    @Test func itemsOnlyShowWhatTheStepOrItsStretchOfTranscriptMentions() {
        let steps = [
            step("Boil soft eggs", "Put the eggs in the pot.", at: 51, items: ["egg", "tangerine", "droplet"]),
            step("Sear chicken mince", "Sear the mince in the wok.", at: 400, items: nil),
        ]
        let grounded = StepItemGrounding.apply(to: steps, transcript: transcript)
        #expect(grounded[0].items == ["egg", "droplet"])          // tangerine was never said
        #expect(grounded[1].items?.contains("poultry_leg") == true || grounded[1].items?.contains("cut_of_meat") == true)
        #expect(grounded[1].items?.contains("tangerine") == false)
    }

    @Test func repeatedItemsAppearOnce() {
        let steps = [step("Boil eggs", "Put the eggs in the water.", at: 51, items: ["egg", "water", "droplet", "egg"])]
        #expect(StepItemGrounding.apply(to: steps, transcript: transcript)[0].items == ["egg", "droplet"])
    }

    @Test func unmentionedItemsFallBackToWhatIsMentioned() {
        // One step covers the whole transcript, so the fallback is everything said, eggs first.
        let steps = [step("Boil eggs", "Boil the eggs.", at: 51, items: ["tangerine"])]
        let items = StepItemGrounding.apply(to: steps, transcript: transcript)[0].items ?? []
        #expect(items.first == "egg")
        #expect(!items.contains("tangerine"))
    }
}
