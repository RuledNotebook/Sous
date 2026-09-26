import UIKit

/// Memory + disk cache in front of any provider, for code that uses the `StepImageProvider` protocol
/// directly. (`StepImageLoader` talks to `StepImageCache` itself and doesn't need this.)
struct CachedImageProvider: StepImageProvider {
    var wrapped: any StepImageProvider
    /// Recorded with each picture; see `StepImageCache`.
    var tier = 0
    var cache: StepImageCache = .shared

    func image(for step: RecipeStep, videoURL: URL?) async -> UIImage? {
        await image(for: StepImageRequest(step: step, videoURL: videoURL))
    }

    func image(for request: StepImageRequest) async -> UIImage? {
        if let hit = await cachedImage(for: request) { return hit }
        guard let image = await wrapped.image(for: request) else { return nil }
        await cache.store(image, tier: tier, for: request.key)
        return image
    }

    /// Only what's already there; never generates.
    func cachedImage(for request: StepImageRequest) async -> UIImage? {
        await cache.entry(for: request.key)?.image
    }
}
