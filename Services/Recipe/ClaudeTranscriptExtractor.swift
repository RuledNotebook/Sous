import Foundation

/// Path C': the transcript goes to Claude (Anthropic Messages API, `ANTHROPIC_API_KEY`) through
/// `CloudRecipeAnalyzer`, whole. Used when there is no OpenAI key.
struct ClaudeTranscriptExtractor: TranscriptRecipeExtractor {
    var analyzer: CloudRecipeAnalyzer

    static func fromInfoPlist(_ bundle: Bundle = .main) -> ClaudeTranscriptExtractor? {
        CloudRecipeAnalyzer.fromInfoPlist(bundle).map { ClaudeTranscriptExtractor(analyzer: $0) }
    }

    var isAvailable: Bool { true }
    var unavailableReason: String? { nil }
    var modelName: String { "Claude \(analyzer.model)" }

    func recipe(from transcript: [TranscriptLine], videoDuration: Double, video: VideoMetadata?) async throws -> Recipe {
        var recipe = try await analyzer.recipe(from: transcript, videoDuration: videoDuration)
        if let video, recipe.title == "Recipe from video", video.title != "YouTube video" { recipe.title = video.title }
        return recipe
    }
}
