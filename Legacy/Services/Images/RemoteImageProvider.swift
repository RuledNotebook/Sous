import CryptoKit
import UIKit

/// The one look every step picture of a recipe shares. Consistency comes from repeating exactly the
/// same setup in every prompt of the series, so edit the words freely but keep them identical across steps.
nonisolated struct RecipeImageStyle: Sendable {
    var camera = "45-degree overhead angle, 50 mm lens, subject centered, shallow depth of field"
    var lighting = "soft diffused daylight from a window on the left, gentle shadows, no harsh highlights"
    var scene = "on a matte light-oak kitchen counter, plain softly blurred neutral background"
    var finish = "natural colors, clean and appetizing, editorial food photography, photorealistic"
    var exclusions = "No text, no logos, no watermark, no people, no hands, no faces."

    func prompt(for request: StepImageRequest, hasReference: Bool) -> String {
        let series = request.recipeTitle.isEmpty
            ? "a step-by-step cooking photo series"
            : "the step-by-step photo series for \"\(request.recipeTitle)\""
        var lines: [String] = []
        if let i = request.stepIndex, let n = request.stepCount {
            lines.append("Photo \(i + 1) of \(n) in \(series).")
        } else {
            lines.append("One photo from \(series).")
        }
        let subject = request.step.imagePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Subject: \(subject.isEmpty ? request.step.title : subject).")
        lines.append("Every photo in the series uses the identical setup: \(camera); \(lighting); \(scene); \(finish).")
        if hasReference {
            lines.append("Match the kitchen in the reference photo (same counter, cookware and light), but keep the frame clean and uncluttered.")
        }
        lines.append(exclusions)
        return lines.joined(separator: " ")
    }
}

/// How to attach the best video frame to a request, for endpoints that accept a reference image.
nonisolated enum ReferenceImageMode: Sendable, Equatable {
    case none
    /// The JSON body gains `"<field>": "data:image/jpeg;base64,…"`.
    case jsonField(String)
    /// The body becomes multipart/form-data with the frame as a JPEG file part
    /// (OpenAI `images/edits` style; point IMAGE_API_URL at that endpoint).
    case multipart(field: String)

    /// Parses IMAGE_API_REFERENCE: "none", "json", "json:<field>", "multipart", "multipart:<field>".
    init(plistValue: String) {
        let parts = plistValue.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let field = parts.count > 1 && !parts[1].isEmpty ? parts[1] : "image"
        switch parts.first?.lowercased() {
        case "json":      self = .jsonField(field)
        case "multipart": self = .multipart(field: field)
        default:          self = .none
        }
    }
}

/// AI step images from any OpenAI-style images endpoint that answers
/// `{ "data": [ { "b64_json": "…" } ] }` (a `"url"` item works too). Adapt `decode` for other providers.
///
/// Info.plist keys: IMAGE_API_URL, IMAGE_API_KEY, IMAGE_API_MODEL, and optionally IMAGE_API_SIZE
/// (default 1024x1024) and IMAGE_API_REFERENCE ("json" or "multipart", see `ReferenceImageMode`).
/// Every failure (no key, no network, a slow or unhappy server) returns nil, so callers keep the video frame.
struct RemoteImageProvider: StepImageProvider {
    var endpoint: URL
    var apiKey: String
    var model: String
    var size = "1024x1024"
    var style = RecipeImageStyle()
    var reference: ReferenceImageMode = .none
    /// Seconds before a request is abandoned.
    var timeout: TimeInterval = 45
    /// Some endpoints (Stability, Flux, …) accept a `seed`; one seed per recipe nudges them towards one
    /// look. Off by default because OpenAI rejects unknown fields.
    var sendsRecipeSeed = false
    /// Extra fields passed through untouched, e.g. ["quality": "medium"].
    var extraFields: [String: String] = [:]
    /// Applied to the result so AI pictures and video frames share the same framing.
    var output = ImageFinisher.Options.card
    /// Grabs a reference frame when the request doesn't already carry one.
    var frames = VideoFrameImageProvider()

    static func fromInfoPlist() -> RemoteImageProvider? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlString = info["IMAGE_API_URL"] as? String, let url = URL(string: urlString),
              let key = info["IMAGE_API_KEY"] as? String, !key.isEmpty else { return nil }
        var provider = RemoteImageProvider(endpoint: url, apiKey: key, model: info["IMAGE_API_MODEL"] as? String ?? "")
        if let size = info["IMAGE_API_SIZE"] as? String, !size.isEmpty { provider.size = size }
        if let mode = info["IMAGE_API_REFERENCE"] as? String { provider.reference = ReferenceImageMode(plistValue: mode) }
        return provider
    }

    func image(for step: RecipeStep, videoURL: URL?) async -> UIImage? {
        await image(for: StepImageRequest(step: step, videoURL: videoURL))
    }

    func image(for request: StepImageRequest) async -> UIImage? {
        guard !apiKey.isEmpty, !Task.isCancelled else { return nil }
        var referenceImage: UIImage?
        if reference != .none {
            if let given = request.referenceImage {
                referenceImage = given
            } else {
                referenceImage = await frames.image(for: request)
            }
        }
        let body = Body(endpoint: endpoint, apiKey: apiKey, model: model,
                        prompt: style.prompt(for: request, hasReference: referenceImage != nil), size: size,
                        seed: sendsRecipeSeed ? Self.seed(for: request.recipeTitle) : nil,
                        extraFields: extraFields, reference: reference, timeout: timeout)
        guard let urlRequest = await Self.makeRequest(body, referenceImage: referenceImage) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return await Self.decode(data, timeout: timeout, output: output)
    }

    // MARK: Wire format

    nonisolated struct Body: Sendable {
        var endpoint: URL
        var apiKey: String
        var model: String
        var prompt: String
        var size: String
        var seed: Int?
        var extraFields: [String: String]
        var reference: ReferenceImageMode
        var timeout: TimeInterval
    }

    /// Builds the request off the main actor (the reference frame is JPEG-encoded and base64'd here).
    @concurrent
    nonisolated static func makeRequest(_ body: Body, referenceImage: UIImage?) async -> URLRequest? {
        var request = URLRequest(url: body.endpoint, timeoutInterval: body.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(body.apiKey)", forHTTPHeaderField: "Authorization")

        var fields: [(String, String)] = []
        if !body.model.isEmpty { fields.append(("model", body.model)) }
        fields.append(("prompt", body.prompt))
        fields.append(("size", body.size))
        if let seed = body.seed { fields.append(("seed", String(seed))) }
        fields += body.extraFields.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        let jpeg = referenceImage?.jpegData(compressionQuality: 0.85)

        if case .multipart(let field) = body.reference, let jpeg {
            let boundary = "cookalong-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipartBody(fields: fields, file: (field, "frame.jpg", "image/jpeg", jpeg), boundary: boundary)
            return request
        }

        var json: [String: Any] = [:]
        for (name, value) in fields { json[name] = name == "seed" ? (Int(value) ?? 0) : value }
        if case .jsonField(let field) = body.reference, let jpeg {
            json[field] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    nonisolated static func multipartBody(fields: [(String, String)],
                                          file: (field: String, name: String, mime: String, data: Data),
                                          boundary: String) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.name)\"\r\n")
        append("Content-Type: \(file.mime)\r\n\r\n")
        body.append(file.data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// `data[0].b64_json`, or `data[0].url` fetched, then framed like every other step picture.
    @concurrent
    nonisolated static func decode(_ data: Data, timeout: TimeInterval, output: ImageFinisher.Options) async -> UIImage? {
        guard let item = (try? JSONDecoder().decode(RemoteImagePayload.self, from: data))?.data.first else { return nil }
        var bytes: Data?
        if let b64 = item.b64_json {
            bytes = Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
        } else if let string = item.url, let url = URL(string: string) {
            bytes = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: timeout)).0
        }
        guard let bytes, let image = UIImage(data: bytes), let cg = image.cgImage else { return nil }
        return UIImage(cgImage: ImageFinisher.finish(cg, options: output))
    }

    /// Stable per-recipe seed for endpoints that honor one.
    nonisolated static func seed(for recipeTitle: String) -> Int {
        let digest = SHA256.hash(data: Data(recipeTitle.lowercased().utf8))
        var value = 0
        for byte in digest.prefix(4) { value = (value << 8) | Int(byte) }
        return value & 0x7FFF_FFFF
    }
}

private nonisolated struct RemoteImagePayload: Decodable {
    nonisolated struct Item: Decodable {
        let b64_json: String?
        let url: String?
    }
    let data: [Item]
}
