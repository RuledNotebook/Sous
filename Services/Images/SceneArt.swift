import Observation
import UIKit
import os

/// Generated scene pictures (the pot, the pan, the bowl) for the step slides, one per `SceneArtKey`,
/// made with the configured images endpoint at its cheapest setting and kept on disk forever.
///
/// Views ask `image(for:)` while drawing; a miss starts one generation for that key and the view
/// redraws when it lands. Nothing configured (no IMAGE_API_KEY) means the slides keep the bundled art.
@Observable @MainActor
final class SceneArtStore {
    static let shared = SceneArtStore.live()

    private(set) var images: [SceneArtKey: UIImage] = [:]

    @ObservationIgnored private let api: (any ImageGenerationAPI)?
    @ObservationIgnored private var requested: Set<SceneArtKey> = []
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let log = Logger(subsystem: "com.cookalong.CookAlong", category: "scene-art")

    var isConfigured: Bool { api != nil }

    init(api: (any ImageGenerationAPI)?, directoryName: String = "SceneArt") {
        self.api = api
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        directory = base?.appending(path: directoryName)
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    /// OpenAI-style endpoint from Info.plist (IMAGE_API_URL, IMAGE_API_KEY, IMAGE_API_MODEL), at the
    /// low-cost transparent-PNG setting these simple pictures need. gpt-image-1-mini is plenty.
    static func live(_ info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> SceneArtStore {
        func text(_ key: String) -> String? {
            guard let value = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        guard let key = text("IMAGE_API_KEY"), let urlString = text("IMAGE_API_URL"), let url = URL(string: urlString) else {
            return SceneArtStore(api: nil)
        }
        var api = OpenAIImagesAPI(endpoint: url, apiKey: key, model: text("IMAGE_API_MODEL") ?? "gpt-image-1-mini")
        api.extraFields = ["quality": "low", "background": "transparent", "output_format": "png"]
        return SceneArtStore(api: api)
    }

    /// The picture for a key if it is ready; otherwise nil now, and a generation starts if possible.
    func image(for key: SceneArtKey) -> UIImage? {
        if let hit = images[key] { return hit }
        guard api != nil, !requested.contains(key) else { return nil }
        requested.insert(key)
        Task { await load(key) }
        return nil
    }

    private func load(_ key: SceneArtKey) async {
        if let file = directory?.appending(path: key.slug + ".png"),
           let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            images[key] = image
            return
        }
        guard let api else { return }
        let job = ImageGenerationJob(prompt: key.prompt, referenceJPEG: nil, seed: nil, timeout: 60)
        guard let data = await Self.generate(api: api, job: job, label: key.slug) else {
            requested.remove(key)   // let a later visit try again
            return
        }
        guard let image = UIImage(data: data) else { return }
        let small = await image.byPreparingThumbnail(ofSize: CGSize(width: 512, height: 512)) ?? image
        images[key] = small
        if let file = directory?.appending(path: key.slug + ".png") {
            try? (small.pngData() ?? data).write(to: file, options: .atomic)
        }
    }

    /// The round trip, off the main actor.
    @concurrent
    nonisolated private static func generate(api: any ImageGenerationAPI, job: ImageGenerationJob, label: String) async -> Data? {
        let log = Logger(subsystem: "com.cookalong.CookAlong", category: "scene-art")
        guard let request = api.makeRequest(job) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                log.error("\(label, privacy: .public): HTTP \(status) \(String(decoding: data.prefix(200), as: UTF8.self), privacy: .public)")
                return nil
            }
            switch api.result(from: data) {
            case .image(let bytes):
                log.info("\(label, privacy: .public): ok, \(bytes.count) bytes")
                return bytes
            case .url(let url):
                return try? await URLSession.shared.data(from: url).0
            case .none:
                log.error("\(label, privacy: .public): no image in the response")
                return nil
            }
        } catch {
            log.error("\(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
