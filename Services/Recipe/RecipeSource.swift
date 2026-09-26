import Foundation

// The YouTube-link -> Recipe entry point. Everything in Services/Recipe/ hangs off these types.
//
// Flow: `RecipeRequest` (a pasted link, optionally a pasted transcript)
//   -> `YouTubeLink.videoID`            parse the link
//   -> `VideoMetadataProvider`          title / channel / thumbnail (YouTube oEmbed, no key)
//   -> path A `TranscriptRecipeExtractor` (pasted transcript, on-device Foundation Models)
//      or path B `VideoRecipeExtractor`   (the video itself, Gemini)
//   -> `SourcedRecipe`

/// What the user gives us.
nonisolated struct RecipeRequest: Sendable, Hashable {
    /// Anything that contains a YouTube link: a share sheet text, a bare URL, or a video ID.
    var link: String
    /// The transcript copied from YouTube's "Show transcript" panel, if the user pasted one.
    var pastedTranscript: String?

    init(link: String, pastedTranscript: String? = nil) {
        self.link = link
        self.pastedTranscript = pastedTranscript
    }
}

/// Public facts about the video. No API key needed.
nonisolated struct VideoMetadata: Sendable, Hashable, Codable {
    var videoID: String
    var title: String
    var channel: String
    var thumbnailURL: URL

    var watchURL: URL { YouTubeLink.watchURL(for: videoID) }
}

/// Which path produced the recipe.
nonisolated enum RecipePath: String, Sendable, Codable {
    /// Transcript the cook pasted, analysed on the device.
    case onDeviceTranscript
    /// YouTube's own captions, fetched by the app and analysed on the device.
    case onDeviceCaptions
    case geminiVideo
}

/// A recipe plus where it came from.
struct SourcedRecipe: Sendable {
    var recipe: Recipe
    var video: VideoMetadata
    var path: RecipePath
}

/// Turns a request into a recipe. The only thing the app needs to call.
@MainActor
protocol RecipeSource {
    func recipe(for request: RecipeRequest) async throws -> SourcedRecipe
}

/// Looks up public video metadata by video ID.
@MainActor
protocol VideoMetadataProvider {
    func metadata(for videoID: String) async throws -> VideoMetadata
}

/// Path A: a recipe from a timestamped transcript, analysed on the device.
@MainActor
protocol TranscriptRecipeExtractor {
    /// False when Apple Intelligence is off or unsupported on this device.
    var isAvailable: Bool { get }
    /// Why `isAvailable` is false, for the error message.
    var unavailableReason: String? { get }
    func recipe(from transcript: [TranscriptLine], videoDuration: Double, video: VideoMetadata?) async throws -> Recipe
}

/// Path B: a recipe from the video itself, analysed in the cloud.
@MainActor
protocol VideoRecipeExtractor {
    func recipe(for video: VideoMetadata) async throws -> Recipe
}

nonisolated enum RecipeSourceError: LocalizedError, Equatable {
    case notAYouTubeLink
    case noVideoInLink
    case videoUnavailable
    case transcriptUnreadable
    /// The app couldn't fetch the video's captions (no captions, private, YouTube changed).
    case transcriptUnavailable(String)
    case nothingAvailable(hasTranscript: Bool, onDeviceReason: String?)
    case cloud(String)

    static let howToCopyTranscript =
        "On YouTube, open the video, tap the ··· menu (or the description), choose \"Show transcript\", select all the text in the panel and copy it."

    var errorDescription: String? {
        switch self {
        case .notAYouTubeLink:
            "That doesn't look like a YouTube link. Paste a link like https://youtu.be/dQw4w9WgXcQ."
        case .noVideoInLink:
            "That YouTube link doesn't point to a video. Open the video itself and copy its link (the one with watch?v= or youtu.be/)."
        case .videoUnavailable:
            "YouTube can't find that video. It may be private, removed, or the link is mistyped."
        case .transcriptUnreadable:
            "The pasted text has no timestamps, so it can't be lined up with the video. \(Self.howToCopyTranscript)"
        case .transcriptUnavailable(let reason):
            "Couldn't get this video's captions from YouTube (\(reason)). \(Self.howToCopyTranscript) Or add GEMINI_API_KEY to Info.plist to analyse the video in the cloud."
        case .nothingAvailable(let hasTranscript, let onDeviceReason):
            if hasTranscript, let onDeviceReason {
                "\(onDeviceReason) So the pasted transcript can't be analysed on this device. Add GEMINI_API_KEY to Info.plist to analyse the video in the cloud instead."
            } else if let onDeviceReason {
                "\(onDeviceReason) Add GEMINI_API_KEY to Info.plist to analyse the video in the cloud."
            } else {
                "Paste the video's transcript to build the recipe on this device. \(Self.howToCopyTranscript) Or add GEMINI_API_KEY to Info.plist to analyse the video in the cloud."
            }
        case .cloud(let detail):
            "The cloud video analysis failed: \(detail)"
        }
    }
}
