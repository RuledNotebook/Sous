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
