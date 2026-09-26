import Foundation
import os

/// Link -> metadata -> the best available path -> Recipe.
///
/// Transcript first: a pasted transcript, else Supadata, else the video's own captions. A cloud
/// model reads the whole transcript when there is a key (OpenAI, else Claude); the small
/// on-device model is the fallback, and never runs when a cloud model is available. Without any
/// transcript, Gemini can watch the video itself. The console gets a model report (which model,
/// how many transcript characters it was sent versus the whole) and the ingredient evidence table.
struct YouTubeRecipeSource: RecipeSource {
    var metadata: any VideoMetadataProvider = YouTubeOEmbedMetadataProvider()
    var transcripts: any TranscriptProvider = YouTubeCaptionsTranscriptProvider()
    /// The default reader of transcripts.
    var transcriptExtractor: any TranscriptRecipeExtractor = OnDeviceTranscriptExtractor()
    /// A cloud model that takes the whole transcript, preferred over the on-device one.
    var cloudExtractor: (any TranscriptRecipeExtractor)?
    /// nil when no Gemini key is configured.
    var videoExtractor: (any VideoRecipeExtractor)?
    /// Console lines (model report, evidence table) also go here, for a debug harness.
    var trace: (@Sendable (String) -> Void)?

    private static let log = Logger(subsystem: "com.cookalong.CookAlong", category: "grounding")

    static func live(bundle: Bundle = .main) -> YouTubeRecipeSource {
        var source = YouTubeRecipeSource(videoExtractor: GeminiVideoRecipeExtractor.fromInfoPlist(bundle))
        // Supadata first when configured, YouTube's own captions as the free fallback.
        if let supadata = SupadataTranscriptProvider.fromInfoPlist(bundle) {
            source.transcripts = FirstWorkingTranscriptProvider(providers: [supadata, YouTubeCaptionsTranscriptProvider()])
        }
        // Whichever cloud key we have reads the whole transcript; on-device only without one.
        source.cloudExtractor = OpenAIRecipeExtractor.fromInfoPlist(bundle) ?? ClaudeTranscriptExtractor.fromInfoPlist(bundle)
        return source
    }

    private func note(_ message: String) {
        Self.log.info("\(message, privacy: .public)")
        NSLog("COOKALONG-GROUNDING %@", message)
        trace?(message)
    }

    /// The extractor for this transcript: the cloud one whenever the default runs on the device
    /// or would thin the transcript, with the report saying why.
    func chooseExtractor(for lines: [TranscriptLine]) -> (extractor: any TranscriptRecipeExtractor, report: ModelReport, reason: String?) {
        let total = TranscriptChunker.render(lines).count
        func report(_ e: any TranscriptRecipeExtractor) -> ModelReport {
            ModelReport(model: e.modelName, transcriptLines: lines.count, transcriptCharacters: total, sentCharacters: e.charactersSent(for: lines))
        }
        let base = transcriptExtractor
        let baseReport = report(base)
        if let cloud = cloudExtractor {
            if base.runsOnDevice {
                return (cloud, report(cloud), "on-device model would be used; switching to \(cloud.modelName) with the full transcript")
            }
            if baseReport.isThinned {
                return (cloud, report(cloud), "\(base.modelName) would thin the transcript; switching to \(cloud.modelName) with the full transcript")
            }
        }
        return (base, baseReport, nil)
    }

    func recipe(for request: RecipeRequest) async throws -> SourcedRecipe {
        let videoID = try YouTubeLink.videoID(from: request.link)
        let video = try await metadata.metadata(for: videoID)
        let pasted = request.pastedTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasTranscript = !pasted.isEmpty

        var transcriptError: RecipeSourceError?
        if transcriptExtractor.isAvailable || cloudExtractor != nil {
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
                let choice = chooseExtractor(for: lines)
                if let reason = choice.reason { note(reason) }
                note(choice.report.description)
                let raw = try await choice.extractor.recipe(from: lines, videoDuration: duration, video: video)
                let grounded = RecipeGrounding.ground(raw, transcript: lines)
                note("ingredients for \(video.title):\n" + grounded.table)
                return SourcedRecipe(recipe: grounded.recipe, video: video, path: path)
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
