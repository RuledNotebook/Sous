import Foundation

/// One kitchen timer. More than one can run at once (pasta + sauce).
struct StepTimer: Identifiable, Hashable, Sendable {
    let id: UUID
    let stepID: RecipeStep.ID
    let title: String
    let length: TimeInterval
    let ends: Date

    init(step: RecipeStep, length: TimeInterval) {
        id = UUID()
        stepID = step.id
        title = step.title
        self.length = length
        ends = .now.addingTimeInterval(length)
    }

    func remaining(at date: Date = .now) -> TimeInterval { max(0, ends.timeIntervalSince(date)) }
    var isDone: Bool { remaining() == 0 }
}
