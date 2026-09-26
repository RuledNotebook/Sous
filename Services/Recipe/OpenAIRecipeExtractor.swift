import Foundation

/// Path C: the transcript goes to OpenAI, which answers with the recipe as strict JSON.
/// Configure `OPENAI_API_KEY` (and optionally `OPENAI_MODEL`) in Config/Secrets.xcconfig.
struct OpenAIRecipeExtractor: TranscriptRecipeExtractor {
    nonisolated static let apiKeyPlistKey = "OPENAI_API_KEY"
    nonisolated static let modelPlistKey = "OPENAI_MODEL"
    nonisolated static let defaultModel = "gpt-5-mini"
    nonisolated static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    /// Keep the prompt well inside the context; a 30 minute video is ~5k words.
    nonisolated static let maxTranscriptCharacters = 60_000

    var apiKey: String
    var model = defaultModel
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    static func fromInfoPlist(_ bundle: Bundle = .main) -> OpenAIRecipeExtractor? {
        guard let key = (bundle.object(forInfoDictionaryKey: apiKeyPlistKey) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        var extractor = OpenAIRecipeExtractor(apiKey: key)
        if let model = (bundle.object(forInfoDictionaryKey: modelPlistKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            extractor.model = model
        }
        return extractor
    }

    var isAvailable: Bool { true }
    var unavailableReason: String? { nil }

    func recipe(from transcript: [TranscriptLine], videoDuration: Double, video: VideoMetadata?) async throws -> Recipe {
        guard !transcript.isEmpty else { throw RecipeAnalysisError.emptyTranscript }
        let request = try makeRequest(transcript: transcript, videoDuration: videoDuration, video: video)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RecipeSourceError.cloud("OpenAI: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw RecipeSourceError.cloud("OpenAI HTTP \(status): \(Self.errorMessage(from: data))")
        }
        var recipe = try Self.parseRecipe(from: data)
        if let video, recipe.title.isEmpty || recipe.title == "Recipe from video", video.title != "YouTube video" {
            recipe.title = video.title
        }
        return recipe
    }

    // MARK: Request

    func makeRequest(transcript: [TranscriptLine], videoDuration: Double, video: VideoMetadata?) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.instructions],
                ["role": "user", "content": Self.userPrompt(transcript: transcript, videoDuration: videoDuration, video: video)],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "recipe", "strict": true, "schema": Self.responseSchema],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    nonisolated static let instructions = """
        You turn the transcript of a cooking video into a recipe a home cook can follow on a phone \
        propped up in the kitchen. Each transcript line starts with the second it was spoken, like [42s]. \
        Merge chatter into real cooking steps, in the order they happen; 5 to 12 steps is typical. For each \
        step give: a 2 to 5 word title starting with a verb; one or two clear sentences; startSecond copied \
        from the transcript line where the step begins; minutes of real kitchen time (not video time; \
        estimate when the video skips ahead); isHandsOn (true for chopping and stirring, false for boiling, \
        baking, resting); needsTimer (true when the cook should set a countdown); one short practical tip \
        or an empty string; and an imagePrompt describing the finished state of the step for an image \
        generator, no people, no text. Also give the dish title, servings, difficulty (easy, medium or hard), \
        the ingredient list with amounts when mentioned, and durationSeconds (the video length, 0 if unknown). \
        Answer only with JSON matching the schema.
        """

    nonisolated static func userPrompt(transcript: [TranscriptLine], videoDuration: Double, video: VideoMetadata?) -> String {
        var lines: [String] = []
        if let video, video.title != "YouTube video" {
            lines.append("Video title: \(video.title)")
            if !video.channel.isEmpty { lines.append("Channel: \(video.channel)") }
        }
        if videoDuration > 0 { lines.append("Video length: \(Int(videoDuration)) seconds") }
        lines.append("Transcript:")
        var rendered = transcript.map { "[\(Int($0.start))s] \($0.text)" }
        // Too long: drop every other line until it fits, so the whole video stays covered.
        while rendered.joined(separator: "\n").count > maxTranscriptCharacters, rendered.count > 20 {
            rendered = rendered.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        }
        return (lines + rendered).joined(separator: "\n")
    }

    /// Strict structured-output schema: every property required, no extras.
    nonisolated static var responseSchema: [String: Any] {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "additionalProperties": false, "required": Array(properties.keys).sorted(), "properties": properties]
        }
        let step = object([
            "title": ["type": "string"],
            "instruction": ["type": "string"],
            "startSecond": ["type": "number"],
            "minutes": ["type": "integer"],
            "isHandsOn": ["type": "boolean"],
            "needsTimer": ["type": "boolean"],
            "tip": ["type": "string"],
            "imagePrompt": ["type": "string"],
        ])
        return object([
            "title": ["type": "string"],
            "servings": ["type": "integer"],
            "difficulty": ["type": "string", "enum": ["easy", "medium", "hard"]],
            "ingredients": ["type": "array", "items": ["type": "string"]],
            "durationSeconds": ["type": "number"],
            "steps": ["type": "array", "items": step],
        ])
    }

    // MARK: Response

    nonisolated private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String?; let refusal: String? }
            let message: Message
            let finish_reason: String?
        }
        let choices: [Choice]
    }

    nonisolated private struct ErrorEnvelope: Decodable {
        struct Inner: Decodable { let message: String?; let type: String?; let code: String? }
        let error: Inner
    }

    static func parseRecipe(from data: Data) throws -> Recipe {
        let chat: ChatResponse
        do { chat = try JSONDecoder().decode(ChatResponse.self, from: data) }
        catch { throw RecipeSourceError.cloud("OpenAI sent an answer this app doesn't understand") }
        guard let choice = chat.choices.first else { throw RecipeSourceError.cloud("OpenAI returned no answer") }
        if let refusal = choice.message.refusal, !refusal.isEmpty {
            throw RecipeSourceError.cloud("OpenAI declined: \(refusal)")
        }
        if choice.finish_reason == "length" {
            throw RecipeSourceError.cloud("the answer was cut off (max tokens)")
        }
        guard let text = choice.message.content, !text.isEmpty else {
            throw RecipeSourceError.cloud("OpenAI returned no text")
        }
        let payload: GeminiVideoRecipeExtractor.Payload
        do { payload = try JSONDecoder().decode(GeminiVideoRecipeExtractor.Payload.self, from: Data(CloudRecipeAnalyzer.stripFences(text).utf8)) }
        catch { throw RecipeSourceError.cloud("recipe JSON didn't match the schema: \(error.localizedDescription)") }
        guard !payload.steps.isEmpty else { throw RecipeAnalysisError.noStepsFound }
        return GeminiVideoRecipeExtractor.recipe(from: payload)
    }

    nonisolated private static func errorMessage(from data: Data) -> String {
        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return [env.error.type, env.error.message].compactMap { $0 }.joined(separator: ": ")
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }
}
