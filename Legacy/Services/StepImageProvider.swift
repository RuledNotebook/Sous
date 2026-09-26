import AVFoundation
import UIKit

/// Anything that can produce a picture for a step.
///
/// The implementations live in `Services/Images/`:
/// - `VideoFrameImageProvider` — best of ~5 frames from the step's slice of the video. No setup, no network.
/// - `RemoteImageProvider`     — AI images from any OpenAI-style endpoint, one consistent look per recipe,
///                               optionally seeded with the best video frame as a reference image.
/// - `FallbackImageProvider`   — try one provider, then another (below).
/// - `CachedImageProvider`     — memory + disk cache in front of any provider.
/// - `StepImageLoader`         — what `CookSession` should call: cached pictures instantly, then video frames
///                               (well under a second), then AI images replacing them; at most 3 requests in
///                               flight, the step the cook is on always first.
/// Providers are configuration values (endpoint, style, sampling options), so they're `Sendable` and can be
/// handed to the loader's child tasks.
@MainActor
protocol StepImageProvider: Sendable {
    /// Minimal entry point: just the step and the video.
    func image(for step: RecipeStep, videoURL: URL?) async -> UIImage?

    /// Richer entry point used by `StepImageLoader`: knows the recipe title and step index (cache key,
    /// series-consistent style), where the step ends (frame sampling window) and, for image-to-image
    /// endpoints, the best picture we already have. Defaults to the minimal one.
    func image(for request: StepImageRequest) async -> UIImage?
}

extension StepImageProvider {
    func image(for request: StepImageRequest) async -> UIImage? {
        await image(for: request.step, videoURL: request.videoURL)
    }
}

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
                             videoURL: videoURL, stepEnd: i + 1 < steps.count ? steps[i + 1].videoStart : nil)
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

/// Try the primary provider first; if it fails or isn't configured, use the fallback.
/// (`StepImageLoader` does this better: it shows the fallback right away and swaps in the primary later.)
struct FallbackImageProvider: StepImageProvider {
    var primary: (any StepImageProvider)?
    var fallback: any StepImageProvider

    func image(for step: RecipeStep, videoURL: URL?) async -> UIImage? {
        await image(for: StepImageRequest(step: step, videoURL: videoURL))
    }

    func image(for request: StepImageRequest) async -> UIImage? {
        if let primary, let img = await primary.image(for: request) { return img }
        return await fallback.image(for: request)
    }
}
