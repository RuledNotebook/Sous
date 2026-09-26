import Foundation

/// One timestamped line of narration, as pasted from YouTube's transcript panel.
nonisolated struct TranscriptLine: Hashable, Sendable {
    let start: Double   // seconds into the video
    let text: String
}
