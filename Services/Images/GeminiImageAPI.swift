import Foundation

/// Google's Gemini image models ("Nano Banana") through the Gemini API, keyed by GEMINI_API_KEY.
/// Request and response shapes checked against ai.google.dev on 2026-09-26:
///
/// - `.interactions` (current): `POST https://generativelanguage.googleapis.com/v1beta/interactions`
///   `{ "model": "gemini-3.1-flash-image", "input": [ { "type": "text", "text": … },
///      { "type": "image", "mime_type": "image/jpeg", "data": <base64> } ] }`
///   The picture comes back base64 in `output_image.data`, or as `{ "type": "image", "data": … }` items
///   inside `steps[].content[]` / `outputs[]`; the decoder accepts any of those.
/// - `.generateContent` (marked legacy, still served): `POST …/v1beta/models/<model>:generateContent`
///   `{ "contents": [ { "parts": [ { "text": … }, { "inline_data": { "mime_type": …, "data": … } } ] } ] }`
///   The picture is in `candidates[0].content.parts[].inlineData.data`.
///
/// Models listed there: gemini-3.1-flash-image (default, GA), gemini-3.1-flash-lite-image (fastest),
/// gemini-3-pro-image (best), gemini-2.5-flash-image (previous generation). All output carries a SynthID watermark.
nonisolated struct GeminiImageAPI: ImageGenerationAPI {
    nonisolated enum Style: String, Sendable {
        case interactions, generateContent

        /// GEMINI_API_STYLE: "interactions" (default) or "generateContent" / "legacy".
        init?(plistValue: String) {
            switch plistValue.lowercased().replacingOccurrences(of: "_", with: "") {
            case "interactions", "interaction": self = .interactions
            case "generatecontent", "legacy":   self = .generateContent
            default:                            return nil
            }
        }
    }

    var apiKey: String
    var model = "gemini-3.1-flash-image"
    var style: Style = .interactions
    /// Override for tests or a proxy (GEMINI_API_URL).
    var baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    var sendsReferenceImage = false
    /// e.g. "3:2" (closest to the 16:10 card) or "16:9". Only sent when set, so the default request is exactly
    /// the documented minimal one; an unsupported value makes the endpoint fail, which shows as a video frame.
    var aspectRatio: String?

    var name: String { "gemini-\(style.rawValue)" }
    var acceptsReferenceImage: Bool { sendsReferenceImage }

    var endpoint: URL? {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        switch style {
        case .interactions:    return URL(string: base + "/v1beta/interactions")
        case .generateContent: return URL(string: base + "/v1beta/models/\(model):generateContent")
        }
    }

    func makeRequest(_ job: ImageGenerationJob) -> URLRequest? {
        guard let endpoint else { return nil }
        var request = URLRequest(url: endpoint, timeoutInterval: job.timeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let reference = job.referenceJPEG?.base64EncodedString()

        var body: [String: Any]
        switch style {
        case .interactions:
            var input: [[String: Any]] = [["type": "text", "text": job.prompt]]
            if let reference { input.append(["type": "image", "mime_type": "image/jpeg", "data": reference]) }
            body = ["model": model, "input": input]
            if let aspectRatio {
                body["response_format"] = ["type": "image", "mime_type": "image/jpeg", "aspect_ratio": aspectRatio]
            }
        case .generateContent:
            var parts: [[String: Any]] = [["text": job.prompt]]
            if let reference { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": reference]]) }
            body = ["contents": [["parts": parts]]]
            if let aspectRatio {
                body["generationConfig"] = ["imageConfig": ["aspectRatio": aspectRatio]]
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = data
        return request
    }

    func result(from body: Data) -> ImageGenerationResult {
        guard let json = try? JSONSerialization.jsonObject(with: body) else { return .none }
        if let b64 = Self.firstInlineImage(in: json),
           let bytes = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) { return .image(bytes) }
        if let uri = Self.firstImageURI(in: json), let url = URL(string: uri) { return .url(url) }
        return .none
    }

    /// Depth-first search for base64 image data, whichever wrapper this API version uses:
    /// `output_image: { data }`, `{ type: "image", data }`, or `inlineData / inline_data: { mimeType, data }`.
    static func firstInlineImage(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let out = dict["output_image"] as? [String: Any], let data = out["data"] as? String, !data.isEmpty { return data }
            if let data = dict["data"] as? String, !data.isEmpty {
                let mime = (dict["mime_type"] ?? dict["mimeType"]) as? String ?? ""
                if dict["type"] as? String == "image" || mime.hasPrefix("image/") { return data }
            }
            for value in dict.values {
                if let hit = firstInlineImage(in: value) { return hit }
            }
        } else if let array = node as? [Any] {
            for item in array {
                if let hit = firstInlineImage(in: item) { return hit }
            }
        }
        return nil
    }

    /// `{ type: "image", uri: … }`, for `delivery: "uri"` responses.
    static func firstImageURI(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if dict["type"] as? String == "image", let uri = dict["uri"] as? String, !uri.isEmpty { return uri }
            for value in dict.values {
                if let hit = firstImageURI(in: value) { return hit }
            }
        } else if let array = node as? [Any] {
            for item in array {
                if let hit = firstImageURI(in: item) { return hit }
            }
        }
        return nil
    }
}
