import Foundation

/// Path B: Gemini watches the YouTube video itself and answers with JSON in the Recipe shape.
///
/// Request format from Google's docs (ai.google.dev, checked 2026-09-26):
/// `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`, the
/// video as a `fileData` part whose `fileUri` is the public watch URL (no upload, no MIME type),
/// and `generationConfig.responseMimeType = application/json` + `responseSchema` to force JSON.
/// `generateContent` remains fully supported; Google now recommends its newer Interactions API
/// for new work, which takes the same video URI as `{"type": "video", "uri": …}`.
///
/// Keys: `GEMINI_API_KEY` (required) and `GEMINI_MODEL` (optional) in Info.plist.
/// Hackathon only: don't ship a key inside an app. Public videos only; the free tier allows
/// 8 hours of YouTube video per day.
struct GeminiVideoRecipeExtractor: VideoRecipeExtractor {
    /// Google's current recommended general-purpose model (docs/models, 2026-09-26).
    static let defaultModel = "gemini-3.8-flash"
    static let apiKeyPlistKey = "GEMINI_API_KEY"
    static let modelPlistKey = "GEMINI_MODEL"

    var apiKey: String
    var model = defaultModel
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300      // the model has to watch the whole video
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    static func fromInfoPlist(_ bundle: Bundle = .main) -> GeminiVideoRecipeExtractor? {
        guard let key = (bundle.object(forInfoDictionaryKey: apiKeyPlistKey) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        var extractor = GeminiVideoRecipeExtractor(apiKey: key)
        if let model = (bundle.object(forInfoDictionaryKey: modelPlistKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            extractor.model = model
        }
        return extractor
    }

    nonisolated static func endpoint(model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    func recipe(for video: VideoMetadata) async throws -> Recipe {
        let request = try makeRequest(for: video)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RecipeSourceError.cloud(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw RecipeSourceError.cloud("HTTP \(status): \(Self.errorMessage(from: data))")
        }
        return try Self.parseRecipe(from: data)
    }

    func makeRequest(for video: VideoMetadata) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint(model: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.requestBody(for: video), options: [.sortedKeys])
        return request
    }

    // MARK: Request

    /// Plain JSON so tests can inspect it without a network.
    nonisolated static func requestBody(for video: VideoMetadata) -> [String: Any] {
        [
            "systemInstruction": ["parts": [["text": instructions]]],
            "contents": [[
                "role": "user",
                "parts": [
                    ["fileData": ["fileUri": video.watchURL.absoluteString]],
                    ["text": prompt(for: video)],
                ],
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": responseSchema,
                "temperature": 0.2,
            ],
        ]
    }

    nonisolated static let instructions = """
        You turn cooking videos into step-by-step recipes a home cook can follow while the video plays. \
        Answer only with JSON matching the schema.

        startSecond: the second in the video when the cook physically BEGINS the action (the knife \
        touches the board, the pan goes on the heat, the tray goes in the oven). Not when the step is \
        first mentioned, planned, or shown in an opening preview. Use what you see, not only what is said.

        minutes: real kitchen time, never video time. Videos cut away from waiting: a bake shown for \
        3 seconds after "into the oven for 25 minutes" is 25. Use spoken or on-screen durations; \
        otherwise estimate what a home cook needs (dice an onion 3 min, bring a pot to the boil 8 min). \
        isHandsOn is false while waiting; needsTimer is true for any wait of a minute or more.

        Merge chatter and repeats into real steps, in the order they happen. Skip intros, sponsor \
        segments and outros. Step titles are 2 to 5 words starting with a verb; instructions are one \
        or two clear sentences with the amounts. Ingredients list every ingredient once with the \
        amount shown or spoken, e.g. "2 chicken breasts, cubed".
        """

    nonisolated static func prompt(for video: VideoMetadata) -> String {
        var lines = ["Watch this cooking video and write the recipe as JSON."]
        if video.title != "YouTube video" { lines.append("Video title: \(video.title)") }
        if !video.channel.isEmpty { lines.append("Channel: \(video.channel)") }
        lines.append("Set durationSeconds to the video's total length in seconds.")
        return lines.joined(separator: "\n")
    }

    /// Gemini's `responseSchema` is an OpenAPI-style subset (uppercase types, `propertyOrdering`).
    nonisolated static var responseSchema: [String: Any] {
        func object(_ properties: [(String, [String: Any])]) -> [String: Any] {
            [
                "type": "OBJECT",
                "properties": Dictionary(uniqueKeysWithValues: properties),
                "required": properties.map(\.0),
                "propertyOrdering": properties.map(\.0),
            ]
        }
        let step = object([
            ("title", ["type": "STRING", "description": "2 to 5 word step title starting with a verb"]),
            ("instruction", ["type": "STRING", "description": "One or two clear sentences with amounts"]),
            ("startSecond", ["type": "INTEGER", "description": "Second in the video when the cook starts this action"]),
            ("minutes", ["type": "INTEGER", "description": "Real kitchen minutes, 1 or more"]),
            ("isHandsOn", ["type": "BOOLEAN"]),
            ("needsTimer", ["type": "BOOLEAN"]),
            ("tip", ["type": "STRING", "description": "One short practical tip, or an empty string"]),
            ("imagePrompt", ["type": "STRING", "description": "Finished state of the step for an image generator, no people or text"]),
        ])
        return object([
            ("title", ["type": "STRING", "description": "Short name of the dish"]),
            ("servings", ["type": "INTEGER", "description": "1 to 12"]),
            ("difficulty", ["type": "STRING", "enum": ["easy", "medium", "hard"]]),
            ("ingredients", ["type": "ARRAY", "items": ["type": "STRING"]]),
            ("durationSeconds", ["type": "INTEGER", "description": "Total length of the video in seconds"]),
            ("steps", ["type": "ARRAY", "items": step]),
        ])
    }

    // MARK: Response

    nonisolated private struct GenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct PromptFeedback: Decodable { let blockReason: String? }
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    nonisolated private struct ErrorEnvelope: Decodable {
        struct Inner: Decodable { let code: Int?; let message: String?; let status: String? }
        let error: Inner
    }

    nonisolated struct Payload: Decodable {
        struct Step: Decodable {
            let title: String
            let instruction: String
            let startSecond: Double
            let minutes: Int
            let isHandsOn: Bool
            let needsTimer: Bool
            let tip: String?
            let imagePrompt: String?
        }
        let title: String
        let servings: Int
        let difficulty: String
        let ingredients: [String]
        let durationSeconds: Double?
        let steps: [Step]
    }

    /// Turns a generateContent response into a Recipe, with the shared clamp/minutes sanity pass.
    static func parseRecipe(from data: Data) throws -> Recipe {
        let message: GenerateContentResponse
        do { message = try JSONDecoder().decode(GenerateContentResponse.self, from: data) }
        catch { throw RecipeSourceError.cloud("not a generateContent response") }

        if let reason = message.promptFeedback?.blockReason {
            throw RecipeSourceError.cloud("Gemini declined this video (\(reason))")
        }
        guard let candidate = message.candidates?.first else {
            throw RecipeSourceError.cloud("Gemini returned no answer")
        }
        if candidate.finishReason == "MAX_TOKENS" {
            throw RecipeSourceError.cloud("the answer was cut off (MAX_TOKENS)")
        }
        if let reason = candidate.finishReason, !["STOP", "FINISH_REASON_UNSPECIFIED"].contains(reason),
           candidate.content?.parts?.contains(where: { $0.text?.isEmpty == false }) != true {
            throw RecipeSourceError.cloud("Gemini stopped early (\(reason))")
        }
        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
        guard !text.isEmpty else { throw RecipeSourceError.cloud("Gemini returned no text") }

        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: Data(CloudRecipeAnalyzer.stripFences(text).utf8)) }
        catch { throw RecipeSourceError.cloud("recipe JSON didn't match the schema: \(error.localizedDescription)") }
        return recipe(from: payload)
    }

    static func recipe(from payload: Payload) -> Recipe {
        let candidates = payload.steps.enumerated().map { order, s in
            StepCandidate(title: s.title, instruction: s.instruction, startSecond: s.startSecond,
                          minutes: s.minutes, isHandsOn: s.isHandsOn, needsTimer: s.needsTimer,
                          tip: s.tip ?? "", imagePrompt: s.imagePrompt ?? "", order: order)
        }
        let ordered = candidates.sorted { ($0.startSecond, $0.order) < ($1.startSecond, $1.order) }
        let steps = ChunkedRecipePipeline.finalize(ordered, videoDuration: payload.durationSeconds ?? 0)
        return Recipe(title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Recipe from video",
                      servings: (1...12).contains(payload.servings) ? payload.servings : 4,
                      difficulty: ["easy", "medium", "hard"].contains(payload.difficulty) ? payload.difficulty
                                  : ChunkedRecipePipeline.difficulty(for: steps),
                      ingredients: ChunkedRecipePipeline.dedupeIngredients(payload.ingredients),
                      steps: steps)
    }

    nonisolated private static func errorMessage(from data: Data) -> String {
        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return [env.error.status, env.error.message].compactMap { $0 }.joined(separator: ": ")
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "unreadable error body"
    }
}
