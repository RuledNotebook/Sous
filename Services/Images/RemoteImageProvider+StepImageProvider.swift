import UIKit

// Bridge added by the foundation session so the app builds while Services/Images/ is being ported:
// `StepImageProvider` now asks for `image(for:in:)`. Session 3: fold this into RemoteImageProvider
// (or replace it) and delete this file.
extension RemoteImageProvider {
    func image(for step: RecipeStep, in recipe: Recipe) async -> UIImage? {
        let steps = recipe.steps
        let index = steps.firstIndex(of: step)
        let stepEnd = index.flatMap { $0 + 1 < steps.count ? Double(steps[$0 + 1].startSecond) : nil }
        return await image(for: StepImageRequest(recipeTitle: recipe.title, stepIndex: index, stepCount: steps.count,
                                                 step: step, videoURL: nil, stepEnd: stepEnd))
    }
}
