import Foundation

/// Recipe analysis with the Anthropic Messages API, for when Apple Intelligence isn't available
/// or the video is too long for the on-device context. One request per video: the model's
/// context is large enough for hours of narration, and structured outputs guarantee JSON.
///
/// Reads `ANTHROPIC_API_KEY` from Info.plist. Hackathon only: don't ship a key inside an app.
struct CloudRecipeAnalyzer: RecipeAnalyzer {
    var apiKey: String
    var model = "claude-opus-5"
    var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    var maxOutputTokens = 16_000
    /// Server-side refusal fallback (beta): if the model declines, the API re-runs the request on
    /// a fallback model. Harmless for cooking videos; disabled automatically if the API rejects it.
    var refusalFallback = true
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 900
        return URLSession(configuration: config)
    }()

    static let infoPlistKey = "ANTHROPIC_API_KEY"

    static func fromInfoPlist(_ bundle: Bundle = .main) -> CloudRecipeAnalyzer? {
        guard let key = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return CloudRecipeAnalyzer(apiKey: key.trimmingCharacters(in: .whitespaces))
    }

    static var isConfigured: Bool { fromInfoPlist() != nil }

    func recipe(from transcript: [TranscriptLine], videoDuration: Double) async throws -> Recipe {
        let lines = transcript.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw RecipeAnalysisError.emptyTranscript }

        var useFallback = refusalFallback
        while true {
            let request = try makeRequest(transcript: lines, videoDuration: videoDuration, refusalFallback: useFallback)
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                return try Self.parseRecipe(from: data, videoDuration: videoDuration)
            }
            let message = Self.errorMessage(from: data)
            // The fallback beta is optional; if this API version rejects it, retry without it.
            if status == 400, useFallback, message.localizedCaseInsensitiveContains("fallback") {
                useFallback = false
                continue
            }
            throw RecipeAnalysisError.http(status, message)
        }
    }

    // MARK: Request

    func makeRequest(transcript: [TranscriptLine], videoDuration: Double, refusalFallback: Bool) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if refusalFallback { request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        let body = Self.requestBody(model: model, maxTokens: maxOutputTokens, transcript: transcript,
                                    videoDuration: videoDuration, refusalFallback: refusalFallback)
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// The Messages API body. Kept as plain JSON so tests can inspect it without a network.
    static func requestBody(model: String, maxTokens: Int, transcript: [TranscriptLine],
                            videoDuration: Double, refusalFallback: Bool) -> [String: Any] {
        let total = Int(videoDuration.rounded())
        let span = total > 0 ? "The video is \(total) seconds long.\n" : ""
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": RecipePrompts.cloudInstructions,
            "messages": [["role": "user", "content": "\(span)Transcript:\n\(TranscriptChunker.render(transcript))"]],
            "output_config": ["format": ["type": "json_schema", "schema": recipeSchema]],
        ]
        if refusalFallback { body["fallbacks"] = "default" }
        return body
    }

    /// JSON schema for structured outputs: every property required, no extras.
    nonisolated static var recipeSchema: [String: Any] {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": Array(properties.keys).sorted(), "additionalProperties": false]
        }
        let step = object([
            "title": ["type": "string", "description": "2 to 5 word step title starting with a verb"],
            "instruction": ["type": "string", "description": "One or two clear sentences a home cook can follow"],
            "startSecond": ["type": "integer", "description": "Second in the video where the cook starts this action"],
            "minutes": ["type": "integer", "description": "Real kitchen minutes for this step, 1 or more"],
            "isHandsOn": ["type": "boolean"],
            "needsTimer": ["type": "boolean"],
            "tip": ["type": "string", "description": "One short practical tip, or an empty string"],
            "imagePrompt": ["type": "string", "description": "Finished state of the step for an image generator, no people or text"],
        ])
        return object([
            "title": ["type": "string", "description": "Short name of the dish"],
            "servings": ["type": "integer", "description": "How many people it serves, 1 to 12"],
            "difficulty": ["type": "string", "enum": ["easy", "medium", "hard"]],
            "ingredients": ["type": "array", "items": object([
                "name": ["type": "string"],
                "amount": ["type": "string", "description": "As said; empty string if no amount is said"],
                "evidence": ["type": "string", "description": "The exact transcript words that name this ingredient"],
                "second": ["type": "integer", "description": "Timestamp of the transcript line the evidence is on"],
            ])],
            "steps": ["type": "array", "items": step],
        ])
    }

    // MARK: Response

    nonisolated private struct MessagesResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
        let stop_reason: String?
    }

    nonisolated private struct ErrorEnvelope: Decodable {
        struct Inner: Decodable { let type: String; let message: String }
        let error: Inner
    }

    typealias Payload = GroundedRecipePayload

    /// Turns a Messages API response into a Recipe, applying the same timestamp clamping and
    /// minute sanity checks as the on-device path. Pure, so it is unit-tested with canned JSON.
    static func parseRecipe(from data: Data, videoDuration: Double) throws -> Recipe {
        let message: MessagesResponse
        do { message = try JSONDecoder().decode(MessagesResponse.self, from: data) }
        catch { throw RecipeAnalysisError.badResponse("not a Messages API response") }

        if message.stop_reason == "refusal" { throw RecipeAnalysisError.refused("safety refusal") }
        if message.stop_reason == "max_tokens" { throw RecipeAnalysisError.badResponse("output was cut off; raise maxOutputTokens") }
        guard let text = message.content.first(where: { $0.type == "text" })?.text else {
            throw RecipeAnalysisError.badResponse("no text block")
        }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: Data(stripFences(text).utf8)) }
        catch { throw RecipeAnalysisError.badResponse("recipe JSON didn't match the schema: \(error.localizedDescription)") }
        return recipe(from: payload, videoDuration: videoDuration)
    }

    static func recipe(from payload: Payload, videoDuration: Double) -> Recipe { payload.recipe(videoDuration: videoDuration) }

    /// Structured outputs return bare JSON; strip a ```json fence anyway in case a model adds one.
    nonisolated static func stripFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.drop(while: { $0 != "\n" }).trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func errorMessage(from data: Data) -> String {
        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) { return "\(env.error.type): \(env.error.message)" }
        return String(data: data.prefix(300), encoding: .utf8) ?? "unreadable error body"
    }
}
