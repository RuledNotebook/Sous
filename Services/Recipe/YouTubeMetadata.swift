import Foundation

/// Title, channel and thumbnail from YouTube's public oEmbed endpoint. No API key.
struct YouTubeOEmbedMetadataProvider: VideoMetadataProvider {
    var session: URLSession = .shared

    static func endpoint(for videoID: String) -> URL {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: YouTubeLink.watchURL(for: videoID).absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url!
    }

    func metadata(for videoID: String) async throws -> VideoMetadata {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: Self.endpoint(for: videoID))
        } catch {
            // Offline or blocked: the recipe can still be built; use the thumbnail YouTube always serves.
            return Self.fallback(for: videoID)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            return (try? Self.parse(data, videoID: videoID)) ?? Self.fallback(for: videoID)
        case 400, 401, 403, 404:
            // oEmbed answers 4xx for private, removed and non-existent videos.
            throw RecipeSourceError.videoUnavailable
        default:
            return Self.fallback(for: videoID)
        }
    }

    nonisolated private struct OEmbed: Decodable {
        let title: String?
        let author_name: String?
        let thumbnail_url: String?
    }

    /// Pure, so tests can feed it canned JSON.
    nonisolated static func parse(_ data: Data, videoID: String) throws -> VideoMetadata {
        let o = try JSONDecoder().decode(OEmbed.self, from: data)
        let thumbnail = o.thumbnail_url.flatMap(URL.init(string:)) ?? YouTubeLink.thumbnailURL(for: videoID)
        return VideoMetadata(videoID: videoID,
                             title: o.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "YouTube video",
                             channel: o.author_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                             thumbnailURL: thumbnail)
    }

    nonisolated static func fallback(for videoID: String) -> VideoMetadata {
        VideoMetadata(videoID: videoID, title: "YouTube video", channel: "", thumbnailURL: YouTubeLink.thumbnailURL(for: videoID))
    }
}

nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
