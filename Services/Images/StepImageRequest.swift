import UIKit

/// Everything a provider might want to know about one step picture.
nonisolated struct StepImageRequest: Sendable {
    var recipeTitle: String
    var stepIndex: Int?
    var stepCount: Int?
    var step: RecipeStep
    var videoURL: URL?
    /// Where the next step starts, so frame sampling stays inside this step. nil = unknown.
    var stepEnd: Double?
    /// Best picture we already have for this step (usually a video frame). Providers that accept a
    /// reference image can send it along so the generated picture matches the real kitchen.
    var referenceImage: UIImage?

    init(recipeTitle: String, stepIndex: Int?, stepCount: Int?, step: RecipeStep, videoURL: URL?,
         stepEnd: Double? = nil, referenceImage: UIImage? = nil) {
        self.recipeTitle = recipeTitle
        self.stepIndex = stepIndex
        self.stepCount = stepCount
        self.step = step
        self.videoURL = videoURL
        self.stepEnd = stepEnd
        self.referenceImage = referenceImage
    }

    /// No recipe context: what the minimal protocol entry point gets.
    init(step: RecipeStep, videoURL: URL?) {
        self.init(recipeTitle: "", stepIndex: nil, stepCount: nil, step: step, videoURL: videoURL)
    }

    /// One request per step, each knowing where the following step begins.
    static func all(for recipe: Recipe, videoURL: URL?) -> [StepImageRequest] {
        let steps = recipe.steps
        return steps.indices.map { i in
            StepImageRequest(recipeTitle: recipe.title, stepIndex: i, stepCount: steps.count, step: steps[i],
                             videoURL: videoURL, stepEnd: i + 1 < steps.count ? Double(steps[i + 1].startSecond) : nil)
        }
    }

    /// Cache identity: recipe title + step index, guarded by a fingerprint of what the picture depends on.
    var key: StepImageKey { StepImageKey(request: self) }

    /// The same request carrying the best picture we have so far.
    func withReference(_ image: UIImage?) -> StepImageRequest {
        var copy = self
        copy.referenceImage = image
        return copy
    }
}

