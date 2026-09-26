import UIKit

/// Loads every step picture for a recipe and hands them over one by one:
/// - anything cached appears immediately;
/// - then each provider tier runs in turn (video frames first because they take under a second, AI images
///   after, replacing the frames), with at most `maxConcurrent` requests in flight and the step the cook is
///   looking at always next in line;
/// - every finished picture goes to the cache tagged with its tier, so re-opening the recipe is instant and a
///   cached frame still gets upgraded to an AI image the next time one can be made.
/// Nothing here throws or blocks: a tier that can't deliver (no key, no network) leaves the previous
/// tier's picture in place.
@MainActor
final class StepImageLoader {
    private let tiers: [any StepImageProvider]
    private let maxConcurrent: Int
    private let cache: StepImageCache
    private var task: Task<Void, Never>?

    /// - Parameter tiers: fastest first; each later tier's picture replaces the earlier one.
    init(tiers: [any StepImageProvider], maxConcurrent: Int = 3, cache: StepImageCache = .shared) {
        self.tiers = tiers
        self.maxConcurrent = max(1, maxConcurrent)
        self.cache = cache
    }

    /// Wraps whatever `CookSession` is already given. A `FallbackImageProvider` is unpacked into two tiers,
    /// its fallback first (that's the fast one) and its primary after, replacing it; anything else is one tier.
    convenience init(provider: any StepImageProvider, maxConcurrent: Int = 3, cache: StepImageCache = .shared) {
        var tiers: [any StepImageProvider] = [provider]
        if let composite = provider as? FallbackImageProvider {
            tiers = [composite.fallback]
            if let primary = composite.primary { tiers.append(primary) }
        }
        self.init(tiers: tiers, maxConcurrent: maxConcurrent, cache: cache)
    }

    /// Video frames, plus AI images when IMAGE_API_URL and IMAGE_API_KEY are set in Info.plist.
    static func standard() -> StepImageLoader {
        var tiers: [any StepImageProvider] = [VideoFrameImageProvider()]
        if let remote = RemoteImageProvider.fromInfoPlist() { tiers.append(remote) }
        return StepImageLoader(tiers: tiers)
    }

    /// Starts loading, cancelling any previous run. `onImage` is called on the main actor, possibly more
    /// than once per step as better pictures arrive. `currentIndex` is read every time a slot frees up,
    /// so the step on screen is always the next one made.
    func start(recipe: Recipe, videoURL: URL?,
               currentIndex: @escaping @MainActor () -> Int,
               onImage: @escaping @MainActor (RecipeStep.ID, UIImage) -> Void) {
        cancel()
        let requests = StepImageRequest.all(for: recipe, videoURL: videoURL)
        task = Task { [tiers, maxConcurrent, cache] in
            await Self.load(requests, tiers: tiers, maxConcurrent: maxConcurrent, cache: cache,
                            currentIndex: currentIndex, onImage: onImage)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static func load(_ requests: [StepImageRequest], tiers: [any StepImageProvider], maxConcurrent: Int,
                             cache: StepImageCache, currentIndex: @escaping @MainActor () -> Int,
                             onImage: @escaping @MainActor (RecipeStep.ID, UIImage) -> Void) async {
        var shownTier: [Int: Int] = [:]     // step index -> tier of the picture on screen
        var latest: [Int: UIImage] = [:]

        // 1. Everything already cached, straight away.
        for (i, request) in requests.enumerated() {
            if Task.isCancelled { return }
            if let entry = await cache.entry(for: request.key) {
                shownTier[i] = entry.tier
                latest[i] = entry.image
                onImage(request.step.id, entry.image)
            }
        }

        // 2. Each tier in turn, `maxConcurrent` at a time, current step first.
        for (tier, provider) in tiers.enumerated() {
            if Task.isCancelled { return }
            let todo = requests.indices.filter { (shownTier[$0] ?? -1) < tier }
            if todo.isEmpty { continue }

            await withTaskGroup(of: (Int, UIImage?).self) { group in
                var pending = Set(todo)
                var running = 0
                while !pending.isEmpty || running > 0 {
                    while running < maxConcurrent, let i = nextIndex(from: &pending, current: currentIndex()) {
                        let request = requests[i].withReference(latest[i])
                        group.addTask { (i, await provider.image(for: request)) }
                        running += 1
                    }
                    guard let (i, image) = await group.next() else { break }
                    running -= 1
                    if Task.isCancelled {
                        group.cancelAll()
                        return
                    }
                    guard let image else { continue }
                    latest[i] = image
                    shownTier[i] = tier
                    onImage(requests[i].step.id, image)
                    await cache.store(image, tier: tier, for: requests[i].key)
                }
            }
        }
    }

    /// The current step if it's still pending, else the next one after it, else the nearest one before it.
    static func nextIndex(from pending: inout Set<Int>, current: Int) -> Int? {
        guard !pending.isEmpty else { return nil }
        let pick = pending.contains(current)
            ? current
            : pending.filter { $0 > current }.min() ?? pending.max() ?? current
        pending.remove(pick)
        return pick
    }
}
