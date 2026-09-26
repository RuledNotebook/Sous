import Foundation

/// Which consecutive steps become one slide, and what to call it.
nonisolated struct SlidePlan: Sendable, Equatable {
    struct Slide: Sendable, Equatable {
        var title: String
        /// Zero-based indices into the step list, consecutive and ascending.
        var stepIndices: [Int]
    }
    var slides: [Slide]
}

/// Turns a long list of small extracted steps into slides a cook can follow.
protocol StepConsolidator: Sendable {
    func plan(for steps: [RecipeStep]) async throws -> SlidePlan
}

nonisolated enum StepConsolidation {
    /// Steps above this count are worth consolidating.
    static let threshold = 9
    /// Steps further apart than this in the video are not one action.
    static let maxGapSeconds = 75
    /// A combined hands-on slide never claims more unspoken minutes than this.
    static let combinedHandsOnCap = 10

    /// A wait worth its own slide: the title says so (boil, bake, rest…) or it is long.
    static func isRealWait(_ step: RecipeStep) -> Bool {
        !step.isHandsOn && (MinutesEstimator.passiveFloor(for: step.title) > 1 || step.minutes >= 10)
    }

    /// Applies a plan, or returns nil when it doesn't cover every step exactly once in order.
    /// Groups are then split where they span a wait or a long gap in the video.
    static func apply(_ plan: SlidePlan, to steps: [RecipeStep]) -> [RecipeStep]? {
        var expected = 0
        var groups: [(title: String, indices: [Int])] = []
        for slide in plan.slides {
            guard let first = slide.stepIndices.first, first == expected,
                  slide.stepIndices == Array(first..<(first + slide.stepIndices.count)),
                  slide.stepIndices.last! < steps.count else { return nil }
            groups.append((slide.title, slide.stepIndices))
            expected = slide.stepIndices.last! + 1
        }
        guard expected == steps.count, !groups.isEmpty else { return nil }
        return groups.flatMap { group in
            split(group.indices, in: steps).enumerated().map { i, part in
                combine(part.map { steps[$0] }, title: i == 0 ? group.title : "")
            }
        }
    }

    /// Cuts a group before and after every real wait, where the vessel changes (board to pan),
    /// and wherever consecutive steps are more than `maxGapSeconds` apart, so a slide is always
    /// one stretch of doing in one place.
    static func split(_ indices: [Int], in steps: [RecipeStep]) -> [[Int]] {
        var parts: [[Int]] = []
        var current: [Int] = []
        for index in indices {
            let step = steps[index]
            if let last = current.last {
                let previous = steps[last]
                let vesselChanged = step.vessel != nil && previous.vessel != nil && step.vessel != previous.vessel
                if isRealWait(step) || isRealWait(previous) || vesselChanged
                    || step.startSecond - previous.startSecond > maxGapSeconds {
                    parts.append(current)
                    current = []
                }
            }
            current.append(index)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// The plan's title, unless it says nothing the steps say (a made-up "Simmer & warm" over
    /// "pour the stock into the bowl"), in which case the first step keeps its own title.
    static func groundedTitle(_ title: String, for group: [RecipeStep]) -> String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let first = group.first else { return group.first?.title ?? "" }
        let planWords = StepMerger.contentWords(cleaned)
        let stepWords = StepMerger.contentWords(group.map { $0.title + " " + $0.instruction }.joined(separator: " "))
        // At least half the title's words must come from the steps ("Boil noodles and vegetables"
        // over "put the water on" shares only "vegetables").
        let shared = planWords.intersection(stepWords).count
        return shared * 2 >= planWords.count && shared > 0 ? cleaned : first.title
    }

    /// One slide from consecutive steps: starts where the first does, keeps a timer if any had
    /// one, shows the finished state of the last. Hands-on minutes add up but stay under
    /// `combinedHandsOnCap` unless a step's time was spoken; a wait keeps its own minutes.
    static func combine(_ group: [RecipeStep], title: String) -> RecipeStep {
        guard let first = group.first else { fatalError("empty group") }
        if group.count == 1 {
            var only = first
            only.title = ChunkedRecipePipeline.capitalized(groundedTitle(title, for: group))
            return only
        }
        var sentences: [String] = []
        for step in group {
            let text = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, !sentences.contains(text) { sentences.append(text) }
        }
        var items: [String] = []
        for item in group.flatMap({ $0.items ?? [] }) where !items.contains(item) { items.append(item) }
        let spoken = group.contains { MinutesEstimator.explicitMinutes(in: $0.title + ". " + $0.instruction) != nil }
        let summed = group.reduce(0) { $0 + $1.minutes }
        let minutes = spoken || group.contains(where: { !$0.isHandsOn }) ? summed : min(summed, combinedHandsOnCap)
        return RecipeStep(title: ChunkedRecipePipeline.capitalized(groundedTitle(title, for: group)),
                          instruction: sentences.joined(separator: " "),
                          startSecond: first.startSecond,
                          minutes: min(minutes, MinutesEstimator.maximumMinutes),
                          isHandsOn: group.contains(where: \.isHandsOn),
                          needsTimer: group.contains(where: \.needsTimer),
                          tip: group.first { !$0.tip.isEmpty }?.tip ?? "",
                          imagePrompt: group.last { !$0.imagePrompt.isEmpty }?.imagePrompt ?? "",
                          vessel: group.last { $0.vessel != nil }?.vessel,
                          items: items.isEmpty ? nil : items)
    }

    /// Rebuilds a sloppy plan from where each slide starts: every step lands in the slide whose
    /// first step precedes it, gaps and overlaps disappear, and step 0 always opens the first slide.
    static func repair(_ plan: SlidePlan, stepCount: Int) -> SlidePlan {
        guard stepCount > 0 else { return SlidePlan(slides: []) }
        var starts: [Int: String] = [0: ""]
        for slide in plan.slides {
            guard let first = slide.stepIndices.min(), first >= 0, first < stepCount else { continue }
            if starts[first] == nil || starts[first]!.isEmpty { starts[first] = slide.title }
        }
        let ordered = starts.keys.sorted()
        var slides: [SlidePlan.Slide] = []
        for (i, start) in ordered.enumerated() {
            let end = i + 1 < ordered.count ? ordered[i + 1] : stepCount
            slides.append(SlidePlan.Slide(title: starts[start] ?? "", stepIndices: Array(start..<end)))
        }
        return SlidePlan(slides: slides)
    }

    /// The numbered list the model plans from: "3. [1:26] Make the teriyaki sauce (2 min, hands-on)".
    static func listing(_ steps: [RecipeStep]) -> String {
        steps.enumerated().map { i, s in
            "\(i + 1). [\(s.startSecond / 60):\(String(format: "%02d", s.startSecond % 60))] \(s.title) (\(s.minutes) min, \(s.isHandsOn ? "hands-on" : "waiting"))"
        }.joined(separator: "\n")
    }

    static func targetCount(for stepCount: Int) -> Int {
        max(6, min(12, stepCount * 2 / 3))
    }
}
