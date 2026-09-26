import Testing
@testable import CookAlong

struct MinutesEstimatorTests {
    @Test(arguments: [
        ("Into the oven for 25 minutes.", 25),
        ("Bake for 20-25 minutes until golden.", 25),
        ("Simmer for 20 to 25 min.", 25),
        ("Let it rest for five minutes.", 5),
        ("Marinate for an hour.", 60),
        ("Braise for an hour and a half.", 90),
        ("Bake one and a half hours.", 90),
        ("Cook 1.5 hrs.", 90),
        ("Sear one minute per side.", 2),
        ("Sear 2 minutes on each side.", 4),
        ("Whisk for 30 seconds.", 1),
        ("Let it sit for a minute or two.", 2),
        ("Cook for a couple of minutes.", 2),
        ("Give it a few minutes.", 3),
        ("Chill for half an hour.", 30),
        ("Roast 45 mins, then rest 10 minutes.", 55),
        ("Proof overnight.", 480),
        ("Twenty five minutes in the oven.", 25),
    ])
    func parsesSpokenDurations(text: String, expected: Int) {
        #expect(MinutesEstimator.explicitMinutes(in: text) == expected)
    }

    @Test func noDurationMeansNil() {
        #expect(MinutesEstimator.explicitMinutes(in: "Add the garlic and stir.") == nil)
        #expect(MinutesEstimator.explicitMinutes(in: "Two cloves of garlic, three tablespoons of butter.") == nil)
    }

    @Test func spokenDurationOverridesAJumpCutEstimate() {
        // The model saw 3 seconds of video and answered 1.
        let m = MinutesEstimator.minutes(model: 1, title: "Bake the salmon", instruction: "Into the oven at 200 degrees for 25 minutes.")
        #expect(m == 25)
        #expect(MinutesEstimator.needsTimer(model: false, title: "Bake the salmon", instruction: "Into the oven for 25 minutes."))
    }

    @Test func passiveVerbsGetARealisticFloorWithoutADuration() {
        #expect(MinutesEstimator.minutes(model: 1, title: "Bake the dish", instruction: "Bake until golden.") >= 20)
        #expect(MinutesEstimator.minutes(model: 1, title: "Boil the water", instruction: "Bring a big pot of salted water to the boil.") >= 8)
        #expect(MinutesEstimator.minutes(model: 1, title: "Let it rest", instruction: "Rest the meat before slicing.") >= 15)
        #expect(MinutesEstimator.minutes(model: 1, title: "Simmer the sauce", instruction: "Let it simmer gently.") >= 15)
    }

    @Test func floorsComeFromTheTitleNotIncidentalWords() {
        // "rest of the butter" is not a rest, "wet shrimp steam" is not steaming.
        #expect(MinutesEstimator.minutes(model: 2, title: "Make the garlic butter", instruction: "Heat down, rest of the butter, the garlic and chili.") == 2)
        #expect(MinutesEstimator.minutes(model: 2, title: "Pat the shrimp dry", instruction: "Paper towel, both sides. Dry shrimp brown, wet shrimp steam.") == 2)
    }

    @Test func capsWildGuessesWhenNothingWasSpoken() {
        #expect(MinutesEstimator.minutes(model: 25, title: "Serve immediately", instruction: "Plate it up.", isHandsOn: true) == MinutesEstimator.handsOnCap)
        #expect(MinutesEstimator.minutes(model: 600, title: "Let the dough rise", instruction: "Cover and leave somewhere warm.", isHandsOn: false) == MinutesEstimator.waitingCap)
        // A spoken duration is never capped.
        #expect(MinutesEstimator.minutes(model: 1, title: "Marinate the chicken", instruction: "Marinate for 6 hours.", isHandsOn: false) == 360)
    }

    @Test func keepsTheModelsNumberForHandsOnWork() {
        #expect(MinutesEstimator.minutes(model: 4, title: "Prep garlic and parsley", instruction: "Thinly slice the garlic and chop the parsley.") == 4)
        #expect(MinutesEstimator.minutes(model: 1, title: "Plate and serve", instruction: "Finish with parsley and serve.") == 1)
    }

    @Test func clampsToSaneBounds() {
        #expect(MinutesEstimator.minutes(model: 0, title: "Stir", instruction: "Stir.") == 1)
        #expect(MinutesEstimator.minutes(model: -3, title: "Stir", instruction: "Stir.") == 1)
        #expect(MinutesEstimator.minutes(model: 1, title: "Cure", instruction: "Cure for 99 hours.") == MinutesEstimator.maximumMinutes)
    }
}
