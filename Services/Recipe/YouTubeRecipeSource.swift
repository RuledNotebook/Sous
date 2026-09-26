import Foundation

/// Link -> metadata -> the best available path -> Recipe.
///
/// Path choice: a pasted transcript with Apple Intelligence available goes on-device (A).
/// Otherwise, with `GEMINI_API_KEY` in Info.plist, the video itself goes to Gemini (B).
/// Otherwise the error says exactly what to do.
struct YouTubeRecipeSource: RecipeSource {
    var metadata: any VideoMetadataProvider = YouTubeOEmbedMetadataProvider()
    var transcriptExtractor: any TranscriptRecipeExtractor = OnDeviceTranscriptExtractor()
    /// nil when no Gemini key is configured.
    var videoExtractor: (any VideoRecipeExtractor)?

    static func live(bundle: Bundle = .main) -> YouTubeRecipeSource {
        YouTubeRecipeSource(videoExtractor: GeminiVideoRecipeExtractor.fromInfoPlist(bundle))
    }

    func recipe(for request: RecipeRequest) async throws -> SourcedRecipe {
        let videoID = try YouTubeLink.videoID(from: request.link)
        let video = try await metadata.metadata(for: videoID)
        let pasted = request.pastedTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasTranscript = !pasted.isEmpty

        if hasTranscript, transcriptExtractor.isAvailable {
            do {
                let lines = try PastedTranscript.parse(pasted)
                let duration = PastedTranscript.estimatedDuration(of: lines)
                let recipe = try await transcriptExtractor.recipe(from: lines, videoDuration: duration)
                return SourcedRecipe(recipe: recipe, video: video, path: .onDeviceTranscript)
            } catch RecipeSourceError.transcriptUnreadable where videoExtractor != nil {
                // The paste wasn't a transcript; the video path doesn't need it.
            }
        }
        if let videoExtractor {
            let recipe = try await videoExtractor.recipe(for: video)
            return SourcedRecipe(recipe: recipe, video: video, path: .geminiVideo)
        }
        throw RecipeSourceError.nothingAvailable(hasTranscript: hasTranscript,
                                                 onDeviceReason: transcriptExtractor.unavailableReason)
    }
}
