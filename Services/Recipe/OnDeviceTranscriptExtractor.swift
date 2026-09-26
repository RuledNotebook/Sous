import Foundation

/// Path A: the pasted transcript goes through the same chunked on-device pipeline as spoken
/// narration (`OnDeviceRecipeAnalyzer`): windows sized for the small context, steps per window,
/// merge, dedupe, clamp. The transcript's own timestamps drive `startSecond`.
struct OnDeviceTranscriptExtractor: TranscriptRecipeExtractor {
    var analyzer = OnDeviceRecipeAnalyzer()

    var isAvailable: Bool { OnDeviceRecipeAnalyzer.isAvailable }
    var unavailableReason: String? { OnDeviceRecipeAnalyzer.unavailableReason }

    func recipe(from transcript: [TranscriptLine], videoDuration: Double, video: VideoMetadata?) async throws -> Recipe {
        let title = video.map { $0.title == "YouTube video" ? nil : $0.title } ?? nil
        return try await analyzer.recipe(from: transcript, videoDuration: videoDuration, videoTitle: title)
    }
}
