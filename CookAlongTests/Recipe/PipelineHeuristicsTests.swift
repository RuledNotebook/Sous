import Foundation
import Testing
@testable import CookAlong

@MainActor
struct StepGroundingTests {
    let lines: [TranscriptLine] = [
        .init(start: 402, text: "get the wok heating up nice and hot"),
        .init(start: 406, text: "and then the chicken mince goes in"),
        .init(start: 410, text: "leave it to sear on that first side"),
        .init(start: 418, text: "while that's going I'll slice the spring onion"),
        .init(start: 424, text: "some gochujang for a spicy smoky flavour"),
        .init(start: 430, text: "and some soy sauce"),
    ]

    private func step(_ title: String, _ instruction: String, at start: Double) -> StepCandidate {
        StepCandidate(title: title, instruction: instruction, startSecond: start, minutes: 2, isHandsOn: true, needsTimer: false)
    }

    @Test func dropsAStepNothingInTheWindowMentions() {
        // The prompt's old worked example, copied verbatim by the model.
        let leaked = step("Dice the onion", "Now the onion, I like a fine dice.", at: 575)
        #expect(StepGrounding.ground([leaked], in: lines).isEmpty)
    }

    @Test func snapsAStepToTheLineWhereItIsSpoken() {
        // Reported at the window start, but the words are spoken at 424 s.
        let late = step("Add gochujang", "Add some gochujang for a spicy, smoky flavour.", at: 402)
        let grounded = StepGrounding.ground([late], in: lines)
        #expect(grounded.map(\.startSecond) == [424])
    }

    @Test func keepsAWellPlacedStepWhereItIs() {
        let sear = step("Sear the mince", "Add the chicken mince to the wok and leave it to sear on the first side.", at: 406)
        #expect(StepGrounding.ground([sear], in: lines).map(\.startSecond) == [406])
    }

    @Test func trustsAStrongMatchEvenFarFromTheReportedTime() {
        let far = step("Slice spring onion", "Slice the spring onion while the mince sears.", at: 1_000)
        var options = StepGrounding.Options()
        options.snapWindow = 10
        #expect(StepGrounding.ground([far], in: lines, options: options).map(\.startSecond) == [418])
    }
}

struct ChatterFilterTests {
    @Test(arguments: [
        ("Welcome to the show", "Hi everyone, welcome to Make It Wednesday."),
        ("Wait for cooking", "I don't know what the time is now, but I think we're less than 15 minutes."),
        ("Thanks for watching", "See you next time."),
        ("Sponsor message", "This video is sponsored by a knife company."),
        ("Subscribe", "Hit the bell and subscribe."),
        ("Continue", "So, um, anyway."),
    ])
    func dropsChatter(title: String, instruction: String) {
        #expect(ChatterFilter.isChatter(title: title, instruction: instruction))
    }

    @Test(arguments: [
        ("Boil the eggs", "Put the eggs in the boiling water and swirl to centre the yolks."),
        ("Sear the mince", "Leave the chicken mince to sear on the first side."),
        ("Rest the meat", "Let the pork rest for five minutes before slicing."),
    ])
    func keepsCooking(title: String, instruction: String) {
        #expect(!ChatterFilter.isChatter(title: title, instruction: instruction))
    }
}

@MainActor
struct StepConsolidationTests {
    private func step(_ title: String, at start: Int, minutes: Int, handsOn: Bool = true, timer: Bool = false, tip: String = "", image: String = "") -> RecipeStep {
        RecipeStep(title: title, instruction: "\(title).", startSecond: start, minutes: minutes, isHandsOn: handsOn,
                   needsTimer: timer, tip: tip, imagePrompt: image)
    }

    let steps = [
        RecipeStep(title: "Sear the mince", instruction: "Leave the mince to sear.", startSecond: 406, minutes: 5, isHandsOn: true, needsTimer: false, tip: "Don't move it.", imagePrompt: "mince searing"),
        RecipeStep(title: "Add spring onion", instruction: "Sprinkle in the spring onion.", startSecond: 418, minutes: 1, isHandsOn: true, needsTimer: false, tip: "", imagePrompt: "onion in wok"),
        RecipeStep(title: "Add gochujang", instruction: "Stir in the gochujang.", startSecond: 424, minutes: 1, isHandsOn: true, needsTimer: false, tip: "", imagePrompt: "red paste in wok"),
        RecipeStep(title: "Boil the noodles", instruction: "Boil the noodles for three minutes.", startSecond: 700, minutes: 3, isHandsOn: false, needsTimer: true, tip: "", imagePrompt: "noodles boiling"),
    ]

    @Test func appliesAValidPlan() throws {
        let plan = SlidePlan(slides: [.init(title: "season the mince", stepIndices: [0, 1, 2]), .init(title: "", stepIndices: [3])])
        let slides = try #require(StepConsolidation.apply(plan, to: steps))
        #expect(slides.count == 2)
        #expect(slides[0].title == "Season the mince")
        #expect(slides[0].startSecond == 406)
        #expect(slides[0].minutes == 7)
        #expect(slides[0].instruction == "Leave the mince to sear. Sprinkle in the spring onion. Stir in the gochujang.")
        #expect(slides[0].tip == "Don't move it.")
        #expect(slides[0].imagePrompt == "red paste in wok")
        #expect(slides[1].title == "Boil the noodles")   // empty plan title keeps the step's own
        #expect(slides[1].needsTimer && !slides[1].isHandsOn)
    }

    @Test(arguments: [
        SlidePlan(slides: [.init(title: "a", stepIndices: [0, 1]), .init(title: "b", stepIndices: [3])]),          // skips 2
        SlidePlan(slides: [.init(title: "a", stepIndices: [0, 2, 1]), .init(title: "b", stepIndices: [3])]),       // not consecutive
        SlidePlan(slides: [.init(title: "a", stepIndices: [1, 2, 3])]),                                             // doesn't start at 0
        SlidePlan(slides: [.init(title: "a", stepIndices: [0, 1, 2, 3, 4])]),                                       // out of range
        SlidePlan(slides: []),
    ])
    func rejectsPlansThatDontCoverEveryStepOnce(plan: SlidePlan) {
        #expect(StepConsolidation.apply(plan, to: steps) == nil)
    }

    @Test func repairsASloppyPlanFromItsSlideStarts() throws {
        // Overlapping, gappy, unordered, and one index out of range; step 0 not mentioned.
        let sloppy = SlidePlan(slides: [
            .init(title: "finish", stepIndices: [3, 9]),
            .init(title: "season", stepIndices: [1, 2]),
            .init(title: "", stepIndices: [1, 3]),
        ])
        let repaired = StepConsolidation.repair(sloppy, stepCount: 4)
        #expect(repaired.slides.map(\.stepIndices) == [[0], [1, 2], [3]])
        #expect(repaired.slides.map(\.title) == ["", "season", "finish"])
        let slides = try #require(StepConsolidation.apply(repaired, to: steps))
        // "season"/"finish" say nothing the grouped steps say, so the first step's title stands.
        #expect(slides.map(\.title) == ["Sear the mince", "Add spring onion", "Boil the noodles"])
        #expect(StepConsolidation.repair(SlidePlan(slides: []), stepCount: 2).slides.map(\.stepIndices) == [[0, 1]])
    }

    @Test func waitsStandAloneAndLongGapsSplitASlide() throws {
        // The model lumps everything into one slide.
        let plan = SlidePlan(slides: [.init(title: "cook it all", stepIndices: [0, 1, 2, 3])])
        let slides = try #require(StepConsolidation.apply(plan, to: steps))
        // 0-2 are one hands-on stretch (406-424 s); 3 is a wait at 700 s.
        #expect(slides.map(\.startSecond) == [406, 700])
        #expect(slides[0].title == "Sear the mince")            // "cook it all" says nothing the steps say
        #expect(slides[1].title == "Boil the noodles")
        #expect(StepConsolidation.split([0, 1, 2, 3], in: steps) == [[0, 1, 2], [3]])

        var farApart = steps
        farApart[2].startSecond = 424 + 200
        #expect(StepConsolidation.split([0, 1, 2], in: farApart) == [[0, 1], [2]])
    }

    @Test func onlyRealWaitsAndVesselChangesSplitASlide() {
        var s = steps
        // A "waiting" step with no wait verb and a small number is just a mislabelled action.
        s[1].isHandsOn = false; s[1].minutes = 3
        #expect(StepConsolidation.split([0, 1, 2], in: s) == [[0, 1, 2]])
        s[1].minutes = 10
        #expect(StepConsolidation.split([0, 1, 2], in: s) == [[0], [1], [2]])
        var v = steps
        v[0].vessel = .pan; v[1].vessel = .pan; v[2].vessel = .bowl
        #expect(StepConsolidation.split([0, 1, 2], in: v) == [[0, 1], [2]])
    }

    @Test func combinedHandsOnMinutesStayRealistic() {
        let eight = (0..<3).map { i in
            RecipeStep(title: ["Grate ginger", "Slice garlic", "Slice bok choy"][i], instruction: "Do it.", startSecond: 200 + i * 20,
                       minutes: 8, isHandsOn: true, needsTimer: false, tip: "", imagePrompt: "")
        }
        #expect(StepConsolidation.combine(eight, title: "Prep aromatics").minutes == StepConsolidation.combinedHandsOnCap)
        var spoken = eight
        spoken[0].instruction = "Grate the ginger, about 10 minutes of work."
        #expect(StepConsolidation.combine(spoken, title: "Prep aromatics").minutes == 24)
    }

    @Test func titleTotalTimeScalesUnspokenMinutes() {
        #expect(TotalTimeHint.minutes(in: "The 15-minute Homemade Ramen You'll Never Get Sick Of | Marion's Kitchen") == 15)
        #expect(TotalTimeHint.minutes(in: "30 Minute Chicken Curry") == 30)
        #expect(TotalTimeHint.minutes(in: "2 hour braise") == 120)
        #expect(TotalTimeHint.minutes(in: "Top 10 mistakes") == nil)
        #expect(TotalTimeHint.minutes(in: nil) == nil)

        let long = [
            RecipeStep(title: "Boil eggs", instruction: "Boil the eggs for 7 minutes.", startSecond: 60, minutes: 7, isHandsOn: false, needsTimer: true, tip: "", imagePrompt: ""),
            RecipeStep(title: "Grate ginger", instruction: "Grate the ginger.", startSecond: 200, minutes: 8, isHandsOn: true, needsTimer: false, tip: "", imagePrompt: ""),
            RecipeStep(title: "Sear mince", instruction: "Sear the mince.", startSecond: 400, minutes: 8, isHandsOn: true, needsTimer: false, tip: "", imagePrompt: ""),
            RecipeStep(title: "Add toppings", instruction: "Add the toppings.", startSecond: 800, minutes: 8, isHandsOn: true, needsTimer: false, tip: "", imagePrompt: ""),
        ]
        let fitted = TotalTimeHint.fit(long, to: 15)
        #expect(fitted[0].minutes == 7)                       // a wait with a spoken time, untouched
        #expect(fitted.dropFirst().allSatisfy { $0.minutes == 5 })   // 24 hands-on minutes -> 15
        #expect(fitted.reduce(0) { $0 + $1.minutes } == 22)
        #expect(TotalTimeHint.fit(long, to: 20) == long)      // 24 hands-on is within reason of 20
        var wait = long
        wait[1].isHandsOn = false; wait[1].instruction = "Simmer the stock."
        #expect(TotalTimeHint.fit(wait, to: 15)[1].minutes == 8)    // waits are never scaled
        var timed = long
        timed[3].needsTimer = true
        let tiny = TotalTimeHint.fit(timed, to: 6)                   // 24 hands-on min -> 6: 2 min each
        #expect(tiny[3].minutes == 2 && !tiny[3].needsTimer)
    }

    @Test func listsStepsForTheModel() {
        let text = StepConsolidation.listing(steps)
        #expect(text.hasPrefix("1. [6:46] Sear the mince (5 min, hands-on)"))
        #expect(text.contains("4. [11:40] Boil the noodles (3 min, waiting)"))
        #expect(StepConsolidation.targetCount(for: 28) == 12)
        #expect(StepConsolidation.targetCount(for: 10) == 6)
    }
}

struct MinutesCapTests {
    @Test func unspokenWaitsNeedAWaitVerb() {
        // "Serve" flagged as waiting with a made-up 15 minutes: capped like hands-on work.
        #expect(MinutesEstimator.minutes(model: 15, title: "Serve", instruction: "Enjoy the ramen immediately.", isHandsOn: false) == MinutesEstimator.handsOnCap)
        // A real wait keeps its estimate.
        #expect(MinutesEstimator.minutes(model: 40, title: "Let the dough rise", instruction: "Cover and leave somewhere warm.", isHandsOn: false) == 40)
        // A spoken duration always wins.
        #expect(MinutesEstimator.minutes(model: 1, title: "Serve", instruction: "Rest for ten minutes first.", isHandsOn: false) == 10)
    }
}

struct CaptionFixesTests {
    @Test func fixesCommonMisHearings() {
        #expect(CaptionFixes.apply(to: "Stir in gacha jang and soy sauce, then heat the walk.") == "Stir in gochujang and soy sauce, then heat the wok.")
        #expect(CaptionFixes.apply(to: "Gotcha Jang paste") == "gochujang paste")
        #expect(CaptionFixes.apply(to: "Take a walk after dinner.") == "Take a wok after dinner.")   // known cost of the map
        #expect(CaptionFixes.apply(to: "Boil the noodles.") == "Boil the noodles.")
    }
}
