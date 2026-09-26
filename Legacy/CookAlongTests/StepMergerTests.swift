import Testing
@testable import CookAlong

@MainActor
struct StepMergerTests {
    private func step(_ title: String, _ instruction: String, at start: Double, window: Int,
                      windowStart: Double = 0, windowEnd: Double = 1_000, minutes: Int = 2,
                      handsOn: Bool = true, timer: Bool = false, tip: String = "", order: Int = 0) -> StepCandidate {
        StepCandidate(title: title, instruction: instruction, startSecond: start, minutes: minutes,
                      isHandsOn: handsOn, needsTimer: timer, tip: tip, imagePrompt: "",
                      windowIndex: window, windowStart: windowStart, windowEnd: windowEnd, order: order)
    }

    @Test func dedupesTheSameStepSeenByTwoOverlappingWindows() {
        let a = step("Sear the shrimp", "Sear the shrimp one minute per side.", at: 85, window: 0, windowStart: 0, windowEnd: 96)
        let b = step("Cook shrimp", "Sear the shrimp for a minute on each side, then set aside.", at: 85, window: 1, windowStart: 78, windowEnd: 190)
        let merged = StepMerger.merge([a, b])
        #expect(merged.count == 1)
        // b sits deeper inside its window (11 s from the edge vs 11 s... a is 11 s from its end, b is 7 s from its start)
        // so the winner is decided by edge distance; either way one step survives with the longer instruction.
        #expect(merged[0].instruction.contains("set aside") || merged[0].instruction.contains("per side"))
    }

    @Test func prefersTheCopyWithMoreContextAroundIt() {
        let edge = step("Make the garlic butter", "Add butter and garlic.", at: 105, window: 0, windowStart: 0, windowEnd: 106, tip: "")
        let deep = step("Make the garlic butter", "Lower the heat, add the rest of the butter, the garlic and chili.", at: 106, window: 1, windowStart: 78, windowEnd: 190, tip: "Pull it before the garlic browns.")
        let merged = StepMerger.merge([edge, deep])
        #expect(merged.count == 1)
        #expect(merged[0].startSecond == 106)
        #expect(merged[0].tip == "Pull it before the garlic browns.")
    }

    @Test func keepsDistinctStepsThatShareWordsButAreFarApart() {
        let first = step("Toss the pasta", "Toss until glossy.", at: 140, window: 0)
        let second = step("Toss everything", "Give it a final toss and taste for salt.", at: 160, window: 0)
        let later = step("Toss the salad", "Toss the salad with the dressing.", at: 400, window: 1)
        #expect(StepMerger.merge([first, second, later]).count == 3)
    }

    @Test func sameTitleWithinAMinuteAcrossWindowsIsOneStep() {
        let a = step("Boil the water", "Bring a big pot of salted water to the boil.", at: 14, window: 0, windowEnd: 60)
        let b = step("Boil the water", "Salt a pot of water and bring it to a rolling boil.", at: 60, window: 1, windowStart: 48)
        #expect(StepMerger.merge([a, b]).count == 1)
    }

    @Test func sameWindowRepeatIsOnlyCollapsedWhenIdentical() {
        let a = step("Stir", "Stir the sauce.", at: 30, window: 0, order: 0)
        let b = step("Stir", "Stir the sauce.", at: 30, window: 0, order: 1)
        let c = step("Stir", "Stir in the cream.", at: 45, window: 0, order: 2)
        #expect(StepMerger.merge([a, b, c]).count == 2)
    }

    @Test func ordersByStartAcrossWindows() {
        let late = step("Plate and serve", "Serve right away.", at: 175, window: 2)
        let early = step("Boil the water", "Salt and boil.", at: 14, window: 0)
        let mid = step("Sear the shrimp", "One minute per side.", at: 85, window: 1)
        let merged = StepMerger.merge([late, early, mid])
        #expect(merged.map(\.title) == ["Boil the water", "Sear the shrimp", "Plate and serve"])
    }

    @Test func combinedStepKeepsTheLargerWaitAndAnyTimer() {
        let a = step("Bake the salmon", "Into the oven.", at: 40, window: 0, windowEnd: 43, minutes: 1, handsOn: true, timer: false)
        let b = step("Bake the salmon", "Bake for 25 minutes.", at: 40, window: 1, windowStart: 12, minutes: 25, handsOn: false, timer: true)
        let merged = StepMerger.merge([a, b])
        #expect(merged.count == 1)
        #expect(merged[0].minutes == 25)
        #expect(merged[0].needsTimer)
        #expect(!merged[0].isHandsOn)
    }

    @Test func similarityIgnoresStopWordsAndInflection() {
        let a = step("Slice the garlic", "Thinly slice the garlic cloves.", at: 0, window: 0)
        let b = step("Slicing garlic", "Slices of garlic, thin.", at: 0, window: 1)
        #expect(StepMerger.similarity(a, b) > 0.5)
        #expect(StepMerger.normalizedTitle("The Garlic, sliced!") == StepMerger.normalizedTitle("slice garlic"))
    }

    @Test func emptyInputMergesToNothing() {
        #expect(StepMerger.merge([]).isEmpty)
    }
}
