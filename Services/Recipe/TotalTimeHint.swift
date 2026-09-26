import Foundation

/// "The 15-minute Homemade Ramen…": a video title that promises a total time is the best
/// estimate we have for unspoken step minutes, which small models guess far too high.
nonisolated enum TotalTimeHint {
    private static let regex = try! NSRegularExpression(
        pattern: #"\b(\d{1,3})\s*[- ]?\s*(minute|min|hour|hr)s?\b"#, options: [.caseInsensitive])

    /// Minutes promised by the title, when it names a plausible total (5 min to 4 h).
    static func minutes(in title: String?) -> Int? {
        guard let title, let m = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let numberRange = Range(m.range(at: 1), in: title), let unitRange = Range(m.range(at: 2), in: title),
              let number = Int(title[numberRange]) else { return nil }
        let unit = title[unitRange].lowercased()
        let total = unit.hasPrefix("h") ? number * 60 : number
        return (5...240).contains(total) ? total : nil
    }

    /// Scales guessed hands-on minutes down so the active work adds up to about `target`.
    /// A "15-minute" promise is about doing, not about waiting: waits (boiling, baking) and
    /// steps with a spoken duration keep their minutes, nothing drops below one minute, and a
    /// hands-on total already within reason (up to 1.25 × target) is left alone.
    static func fit(_ steps: [RecipeStep], to target: Int) -> [RecipeStep] {
        let guessed = steps.map { $0.isHandsOn && MinutesEstimator.explicitMinutes(in: $0.title + ". " + $0.instruction) == nil }
        let handsOnSum = steps.filter(\.isHandsOn).reduce(0) { $0 + $1.minutes }
        guard handsOnSum > Int(Double(target) * 1.25) else { return steps }
        let guessedSum = zip(steps, guessed).filter(\.1).reduce(0) { $0 + $1.0.minutes }
        guard guessedSum > 0 else { return steps }
        let budget = max(target - (handsOnSum - guessedSum), 0)
        let factor = Double(budget) / Double(guessedSum)
        return zip(steps, guessed).map { step, isGuess in
            guard isGuess else { return step }
            var out = step
            out.minutes = max(1, Int((Double(step.minutes) * factor).rounded()))
            if out.minutes < 3 { out.needsTimer = false }   // a guessed one-minute step needs no timer
            return out
        }
    }
}
