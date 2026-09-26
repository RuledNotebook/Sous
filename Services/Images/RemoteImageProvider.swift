import CryptoKit
import UIKit
import os

/// The one look every step picture of a recipe shares. Consistency comes from repeating exactly the
/// same setup in every prompt of the series, so edit the words freely but keep them identical across steps.
nonisolated struct RecipeImageStyle: Sendable {
    var camera = "45-degree overhead angle, 50 mm lens, subject centered, shallow depth of field"
    var lighting = "soft diffused daylight from a window on the left, gentle shadows, no harsh highlights"
    var surface = "on a matte light-oak kitchen counter"
    var background = "plain, softly blurred neutral kitchen background"
    var finish = "natural colors, clean and appetizing, editorial food photography, photorealistic"
    var exclusions = "No text, no letters, no logos, no watermark, no people, no hands, no faces."

    /// Recipe title + the step's image prompt + the fixed style block.
    func prompt(recipeTitle: String, stepIndex: Int?, stepCount: Int, imagePrompt: String, stepTitle: String,
                hasReference: Bool) -> String {
        let series = recipeTitle.isEmpty
            ? "a step-by-step cooking photo series"
            : "the step-by-step photo series for \"\(recipeTitle)\""
        var lines: [String] = []
        if let stepIndex {
            lines.append("Photo \(stepIndex + 1) of \(stepCount) in \(series).")
        } else {
            lines.append("One photo from \(series).")
        }
        let subject = imagePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Subject: \(subject.isEmpty ? stepTitle : subject).")
        lines.append("Every photo in the series uses the identical setup: \(camera); \(lighting); \(surface); \(background); \(finish).")
        if hasReference {
            lines.append("Match the kitchen in the reference photo (same counter, cookware and light), but keep the frame clean and uncluttered.")
        }
        lines.append(exclusions)
        return lines.joined(separator: " ")
    }
}

/// One AI picture per call through any `ImageGenerationAPI`, with one consistent look per recipe.
/// Wrap it in `StepImageService` for caching and concurrency; `StepImages.live()` does exactly that.
///
/// Info.plist decides the endpoint (`fromInfoPlist`):
/// - `IMAGE_API_URL` + `IMAGE_API_KEY` (+ `IMAGE_API_MODEL`, `IMAGE_API_SIZE`, `IMAGE_API_REFERENCE`): any
///   OpenAI-style images endpoint, see `OpenAIImagesAPI`.
/// - else `GEMINI_API_KEY` (+ `GEMINI_IMAGE_MODEL`, `GEMINI_API_STYLE`, `GEMINI_ASPECT_RATIO`, `GEMINI_API_URL`,
///   and `IMAGE_API_REFERENCE` = "yes" to send the video thumbnail along): Gemini, see `GeminiImageAPI`.
/// - neither: nil, so the slides keep their placeholders.
/// Every failure (no network, a slow or unhappy server, an unreadable answer) is logged under the
/// "images" category and returns nil.
struct RemoteImageProvider: StepImageProvider {
    var api: any ImageGenerationAPI
    var style = RecipeImageStyle()
    /// Seconds before a request is abandoned. Image models routinely take 10–30 s.
    var timeout: TimeInterval = 60
    /// Some endpoints accept a `seed`; one seed per recipe nudges them towards one look. Off by default
    /// because OpenAI rejects unknown fields.
    var sendsRecipeSeed = false
    var output = ImageFinisher.Options.slide

    static func fromInfoPlist(_ info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> RemoteImageProvider? {
        func text(_ key: String) -> String? {
            guard let value = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        let reference = ReferenceImageMode(plistValue: text("IMAGE_API_REFERENCE") ?? "")
        if let key = text("IMAGE_API_KEY"), let urlString = text("IMAGE_API_URL"), let url = URL(string: urlString) {
            var api = OpenAIImagesAPI(endpoint: url, apiKey: key, model: text("IMAGE_API_MODEL") ?? "", reference: reference)
            if let size = text("IMAGE_API_SIZE") { api.size = size }
            return RemoteImageProvider(api: api)
        }
        if let key = text("GEMINI_API_KEY") {
            var api = GeminiImageAPI(apiKey: key)
            if let model = text("GEMINI_IMAGE_MODEL") { api.model = model }
            if let style = text("GEMINI_API_STYLE").flatMap(GeminiImageAPI.Style.init(plistValue:)) { api.style = style }
            if let base = text("GEMINI_API_URL").flatMap(URL.init(string:)) { api.baseURL = base }
            api.aspectRatio = text("GEMINI_ASPECT_RATIO")
            api.sendsReferenceImage = reference != .none
            return RemoteImageProvider(api: api)
        }
        return nil
    }

    func image(for step: RecipeStep, in recipe: Recipe) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let index = recipe.steps.firstIndex { $0.id == step.id }
        var reference: Data?
        if api.acceptsReferenceImage, let thumbnail = recipe.thumbnailURL {
            reference = await ReferencePictures.shared.jpeg(for: thumbnail)
        }
        let prompt = style.prompt(recipeTitle: recipe.title, stepIndex: index, stepCount: recipe.steps.count,
                                  imagePrompt: step.imagePrompt, stepTitle: step.title, hasReference: reference != nil)
        let job = ImageGenerationJob(prompt: prompt, referenceJPEG: reference,
                                     seed: sendsRecipeSeed ? Self.seed(for: recipe) : nil, timeout: timeout)
        let label = "\(recipe.title) step \(index.map { $0 + 1 } ?? 0)"
        return await Self.generate(api: api, job: job, output: output, label: label)
    }

    /// The whole round trip, off the main actor: call the endpoint, decode, downscale.
    @concurrent
    nonisolated static func generate(api: any ImageGenerationAPI, job: ImageGenerationJob,
                                     output: ImageFinisher.Options, label: String) async -> UIImage? {
        let log = Logger(subsystem: "com.cookalong.CookAlong", category: "images")
        guard let request = api.makeRequest(job) else {
            log.error("\(api.name, privacy: .public): couldn't build a request for \(label, privacy: .public)")
            return nil
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.error("\(api.name, privacy: .public): \(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let excerpt = String(decoding: data.prefix(300), as: UTF8.self)
            log.error("\(api.name, privacy: .public): \(label, privacy: .public) HTTP \(status): \(excerpt, privacy: .public)")
            return nil
        }
        var bytes: Data?
        switch api.result(from: data) {
        case .image(let encoded):
            bytes = encoded
        case .url(let url):
            bytes = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: job.timeout)).0
        case .none:
            log.error("\(api.name, privacy: .public): no image in the response for \(label, privacy: .public)")
        }
        guard let bytes, let image = UIImage(data: bytes), let cg = image.cgImage else { return nil }
        log.info("\(api.name, privacy: .public): \(label, privacy: .public) ok, \(cg.width)x\(cg.height)")
        return UIImage(cgImage: ImageFinisher.finish(cg, options: output))
    }

    /// Stable per-recipe seed for endpoints that honor one: the video ID when there is one, else the title.
    nonisolated static func seed(for recipe: Recipe) -> Int {
        let material = (recipe.videoID ?? recipe.title).lowercased()
        let digest = SHA256.hash(data: Data(material.utf8))
        var value = 0
        for byte in digest.prefix(4) { value = (value << 8) | Int(byte) }
        return value & 0x7FFF_FFFF
    }
}

/// Reference pictures (the recipe's YouTube thumbnail) fetched once per URL and kept as JPEG bytes.
actor ReferencePictures {
    static let shared = ReferencePictures()

    private var pictures: [URL: Data] = [:]
    private var inflight: [URL: Task<Data?, Never>] = [:]

    func jpeg(for url: URL) async -> Data? {
        if let hit = pictures[url] { return hit }
        if let task = inflight[url] { return await task.value }
        let task = Task<Data?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15)),
                  let image = UIImage(data: data) else { return nil }
            return image.jpegData(compressionQuality: 0.85)
        }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        if let result { pictures[url] = result }
        return result
    }
}
