import UIKit

/// The slides draw their own scenes from the bundled Kitchen art (see `KitchenAssets`, `StepSceneView`),
/// so the default path generates nothing. `RemoteImageProvider` and `StepImageService` stay available for an
/// AI-picture experiment: `StepImageService(generator: RemoteImageProvider.fromInfoPlist()!)`.
enum StepImages {
    @MainActor
    static func live() -> any StepImageProvider {
        NoStepImages()
    }
}

/// Caching and scheduling in front of a one-picture-at-a-time generator.
///
/// `CookSession` asks for one step at a time, current step first. The first ask for a recipe starts
/// generation for every step at once, `maxConcurrent` in flight (so the first steps are ready while the
/// cook reads the ingredients and the rest arrive in the background), and each later ask moves that step
/// to the front of the queue. Pictures go to memory and disk, so reopening a recipe is instant, and a
/// new recipe cancels whatever the previous one still had queued.
@MainActor
final class StepImageService: StepImageProvider {
    private let generator: any StepImageProvider
    private let cache: StepImageCache
    private let gate: PriorityGate
    private var recipeID: Recipe.ID?
    private var tasks: [RecipeStep.ID: Task<UIImage?, Never>] = [:]

    init(generator: any StepImageProvider, maxConcurrent: Int = 3, cache: StepImageCache = .shared) {
        self.generator = generator
        self.cache = cache
        gate = PriorityGate(limit: maxConcurrent)
    }

    func image(for step: RecipeStep, in recipe: Recipe) async -> UIImage? {
        let key = StepImageKey(recipe: recipe, step: step)
        if let hit = await cache.image(for: key) { return hit }
        if recipeID != recipe.id { start(recipe) }
        guard let task = tasks[step.id] else { return nil }
        await gate.raise(id: step.id)
        return await task.value
    }

    /// Drops whatever is queued (running requests finish and still land in the cache).
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        recipeID = nil
    }

    private func start(_ recipe: Recipe) {
        cancelAll()
        recipeID = recipe.id
        for (index, step) in recipe.steps.enumerated() {
            tasks[step.id] = Task { [generator, cache, gate] in
                let key = StepImageKey(recipe: recipe, step: step)
                if let hit = await cache.image(for: key) { return hit }
                guard await gate.acquire(id: step.id, priority: index) else { return nil }
                let image = Task.isCancelled ? nil : await generator.image(for: step, in: recipe)
                await gate.release()
                if let image { await cache.store(image, for: key) }
                return image
            }
        }
    }
}
