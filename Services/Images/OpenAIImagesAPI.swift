import Foundation

/// How to attach the best video frame to a request, for endpoints that accept a reference image.
nonisolated enum ReferenceImageMode: Sendable, Equatable {
    case none
    /// The JSON body gains `"<field>": "data:image/jpeg;base64,…"`.
    case jsonField(String)
    /// The body becomes multipart/form-data with the frame as a JPEG file part
    /// (OpenAI `images/edits` style; point IMAGE_API_URL at that endpoint).
    case multipart(field: String)

    /// Parses IMAGE_API_REFERENCE: "none", "json", "json:<field>", "multipart", "multipart:<field>".
    /// Anything else non-empty ("yes", say) counts as `.jsonField("image")` so Gemini users can just say yes.
    init(plistValue: String) {
        let parts = plistValue.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let field = parts.count > 1 && !parts[1].isEmpty ? parts[1] : "image"
        switch parts.first?.lowercased() {
        case nil, "", "none", "no", "false", "0": self = .none
        case "multipart":                         self = .multipart(field: field)
        default:                                  self = .jsonField(field)
        }
    }
}

/// Any OpenAI-style images endpoint: JSON `{ "model", "prompt", "size" }` in,
/// `{ "data": [ { "b64_json": … } ] }` (or `{ "url": … }`) out.
/// With `.multipart` reference mode the body becomes multipart/form-data, which is what OpenAI's `images/edits` takes.
nonisolated struct OpenAIImagesAPI: ImageGenerationAPI {
    var endpoint: URL
    var apiKey: String
    var model: String
    /// "1024x1024" works everywhere; gpt-image-1 also takes "1536x1024", DALL·E 3 "1792x1024" (closer to the 16:10 card).
    var size = "1024x1024"
    var reference: ReferenceImageMode = .none
    /// Extra fields passed through untouched, e.g. ["quality": "medium"].
    var extraFields: [String: String] = [:]

    var name: String { "openai-images" }
    var acceptsReferenceImage: Bool { reference != .none }

    func makeRequest(_ job: ImageGenerationJob) -> URLRequest? {
        var request = URLRequest(url: endpoint, timeoutInterval: job.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var fields: [(String, String)] = []
        if !model.isEmpty { fields.append(("model", model)) }
        fields.append(("prompt", job.prompt))
        fields.append(("size", size))
        if let seed = job.seed { fields.append(("seed", String(seed))) }
        fields += extraFields.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

        if case .multipart(let field) = reference, let jpeg = job.referenceJPEG {
            let boundary = "cookalong-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.multipartBody(fields: fields, file: (field, "frame.jpg", "image/jpeg", jpeg), boundary: boundary)
            return request
        }

        var json: [String: Any] = [:]
        for (name, value) in fields { json[name] = name == "seed" ? (Int(value) ?? 0) : value }
        if case .jsonField(let field) = reference, let jpeg = job.referenceJPEG {
            json[field] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    func result(from body: Data) -> ImageGenerationResult {
        guard let item = (try? JSONDecoder().decode(Payload.self, from: body))?.data.first else { return .none }
        if let b64 = item.b64_json, let bytes = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) { return .image(bytes) }
        if let string = item.url, let url = URL(string: string) { return .url(url) }
        return .none
    }

    private nonisolated struct Payload: Decodable {
        nonisolated struct Item: Decodable {
            let b64_json: String?
            let url: String?
        }
        let data: [Item]
    }

    static func multipartBody(fields: [(String, String)],
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
}
