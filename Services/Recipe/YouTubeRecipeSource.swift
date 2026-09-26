import Foundation

/// Link -> metadata -> the best available path -> Recipe.
///
/// Path choice, with Apple Intelligence available: a pasted transcript, else the video's own
/// captions fetched from YouTube, analysed on-device (A). Otherwise, with `GEMINI_API_KEY` in
/// Info.plist, the video itself goes to Gemini (B). Otherwise the error says exactly what to do.
struct YouTubeRecipeSource: RecipeSource {
    var metadata: any VideoMetadataProvider = YouTubeOEmbedMetadataProvider()
    var transcripts: any TranscriptProvider = YouTubeCaptionsTranscriptProvider()
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

        var transcriptError: RecipeSourceError?
        if transcriptExtractor.isAvailable {
            var lines: [TranscriptLine] = []
            var duration = 0.0
            var path = RecipePath.onDeviceTranscript
            if hasTranscript {
                do {
                    lines = try PastedTranscript.parse(pasted)
                    duration = PastedTranscript.estimatedDuration(of: lines)
                } catch let error as RecipeSourceError {
                    transcriptError = error   // not a transcript; try YouTube's captions instead
                }
            }
            if lines.isEmpty {
                do {
                    let fetched = try await transcripts.transcript(for: videoID)
                    lines = fetched.lines
                    duration = fetched.duration ?? PastedTranscript.estimatedDuration(of: fetched.lines)
                    path = .onDeviceCaptions
                } catch let error as RecipeSourceError {
                    transcriptError = transcriptError ?? error
                }
            }
            if !lines.isEmpty {
                let recipe = try await transcriptExtractor.recipe(from: lines, videoDuration: duration, video: video)
                return SourcedRecipe(recipe: recipe, video: video, path: path)
            }
        }
        if let videoExtractor {
            let recipe = try await videoExtractor.recipe(for: video)
            return SourcedRecipe(recipe: recipe, video: video, path: .geminiVideo)
        }
        if let transcriptError { throw transcriptError }
        throw RecipeSourceError.nothingAvailable(hasTranscript: hasTranscript,
                                                 onDeviceReason: transcriptExtractor.unavailableReason)
    }
}
