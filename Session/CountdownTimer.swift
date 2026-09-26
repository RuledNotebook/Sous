import Foundation

/// The one kitchen timer. Started from a step's real-world minutes.
nonisolated struct CountdownTimer: Equatable, Sendable {
    let stepID: RecipeStep.ID
    let stepTitle: String
    let length: TimeInterval
    let ends: Date

    init(step: RecipeStep, secondsPerMinute: Double = 60) {
        stepID = step.id
        stepTitle = step.title
        length = Double(max(step.minutes, 1)) * secondsPerMinute
        ends = .now.addingTimeInterval(length)
    }

    func remaining(at date: Date) -> TimeInterval { max(0, ends.timeIntervalSince(date)) }
    func progress(at date: Date) -> Double { length > 0 ? 1 - remaining(at: date) / length : 1 }
}
