import UIKit

// Owned by session 3 (Services/Images/). CookSession only knows this protocol.

/// A picture for one step. Return nil when there is none; the slide shows a placeholder.
/// Called once per step, current step first, on the main actor; do the work off it.
@MainActor
protocol StepImageProvider {
    func image(for step: RecipeStep, in recipe: Recipe) async -> UIImage?
}

/// Stand-in until the real provider lands: every slide keeps its placeholder.
struct NoStepImages: StepImageProvider {
    func image(for step: RecipeStep, in recipe: Recipe) async -> UIImage? { nil }
}
