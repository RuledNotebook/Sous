import Foundation

/// Pulls the 11-character video ID out of anything YouTube hands out.
///
/// Handles `watch?v=`, `youtu.be/`, `/shorts/`, `/embed/`, `/live/`, `/v/`, the mobile and
/// music hosts, links without a scheme, extra query parameters (`&t=30s`, `?si=…`), a bare
/// video ID, and a share-sheet blurb with the link somewhere inside it.
nonisolated enum YouTubeLink {
    static let hosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "gaming.youtube.com",
        "youtube-nocookie.com", "www.youtube-nocookie.com", "youtu.be", "www.youtu.be",
    ]
    private static let idRegex = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_-]{11}$"#)

    static func isVideoID(_ candidate: String) -> Bool {
        idRegex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)) != nil
    }

    static func watchURL(for videoID: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }

    /// YouTube serves this for every public video; `maxresdefault` exists only for some.
    static func thumbnailURL(for videoID: String) -> URL {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")!
    }

    /// The video ID in `text`, or a `RecipeSourceError` saying what is wrong with it.
    static func videoID(from text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecipeSourceError.notAYouTubeLink }
        if isVideoID(trimmed) { return trimmed }

        // A share-sheet blurb: "Check this out https://youtu.be/… via @YouTube". Take the link inside.
        let candidate = trimmed.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first { $0.localizedCaseInsensitiveContains("youtu") } ?? trimmed

        guard let components = normalizedComponents(of: candidate),
              let host = components.host?.lowercased(), hosts.contains(host) else {
            throw RecipeSourceError.notAYouTubeLink
        }

        let path = components.path.split(separator: "/").map(String.init)
        let query = components.queryItems ?? []
        var id: String?

        if host.hasSuffix("youtu.be") {
            id = path.first
        } else if path.first == "watch" {
            id = query.first { $0.name == "v" }?.value ?? (path.count > 1 ? path[1] : nil)
        } else if let first = path.first, ["shorts", "embed", "live", "v", "e"].contains(first), path.count > 1 {
            id = path[1]
        } else if let v = query.first(where: { $0.name == "v" })?.value {
            id = v   // e.g. youtube.com/?v=ID, attribution links that kept the query
        }

        guard let id = id?.trimmingCharacters(in: .whitespaces), !id.isEmpty else {
            throw RecipeSourceError.noVideoInLink
        }
        guard isVideoID(id) else { throw RecipeSourceError.noVideoInLink }
        return id
    }

    /// `youtu.be/x` -> `https://youtu.be/x`; strips surrounding punctuation from pasted text.
    private static func normalizedComponents(of raw: String) -> URLComponents? {
        var text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]\"'.,;"))
        if !text.lowercased().hasPrefix("http://"), !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let components = URLComponents(string: text) else { return nil }
        return components
    }
}
