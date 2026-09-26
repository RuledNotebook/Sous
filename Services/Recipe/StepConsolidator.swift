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

    /// Applies a plan, or returns nil when it doesn't cover every step exactly once in order.
    static func apply(_ plan: SlidePlan, to steps: [RecipeStep]) -> [RecipeStep]? {
        var expected = 0
        var out: [RecipeStep] = []
        for slide in plan.slides {
            guard let first = slide.stepIndices.first, first == expected,
                  slide.stepIndices == Array(first..<(first + slide.stepIndices.count)),
                  slide.stepIndices.last! < steps.count else { return nil }
            out.append(combine(slide.stepIndices.map { steps[$0] }, title: slide.title))
            expected = slide.stepIndices.last! + 1
        }
        guard expected == steps.count, !out.isEmpty else { return nil }
        return out
    }

    /// One slide from consecutive steps: starts where the first does, takes all their minutes,
    /// keeps a timer if any had one, and shows the finished state of the last.
    static func combine(_ group: [RecipeStep], title: String) -> RecipeStep {
        guard let first = group.first else { fatalError("empty group") }
        if group.count == 1 {
            var only = first
            let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { only.title = ChunkedRecipePipeline.capitalized(cleaned) }
            return only
        }
        var sentences: [String] = []
        for step in group {
            let text = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, !sentences.contains(text) { sentences.append(text) }
        }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [String] = []
        for item in group.flatMap({ $0.items ?? [] }) where !items.contains(item) { items.append(item) }
        return RecipeStep(title: ChunkedRecipePipeline.capitalized(cleaned.isEmpty ? first.title : cleaned),
                          instruction: sentences.joined(separator: " "),
                          startSecond: first.startSecond,
                          minutes: min(group.reduce(0) { $0 + $1.minutes }, MinutesEstimator.maximumMinutes),
                          isHandsOn: group.contains(where: \.isHandsOn),
                          needsTimer: group.contains(where: \.needsTimer),
                          tip: group.first { !$0.tip.isEmpty }?.tip ?? "",
                          imagePrompt: group.last { !$0.imagePrompt.isEmpty }?.imagePrompt ?? "",
                          vessel: group.last { $0.vessel != nil }?.vessel,
                          items: items.isEmpty ? nil : items)
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
