import Foundation
import Testing
@testable import CookAlong

struct YouTubeLinkTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s&list=PL123&index=2",
        "https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abcDEF123&t=12",
        "youtu.be/dQw4w9WgXcQ",
        "youtube.com/watch?v=dQw4w9WgXcQ",
        "www.youtube.com/watch?v=dQw4w9WgXcQ",
        "http://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ&feature=share",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://youtube.com/shorts/dQw4w9WgXcQ?feature=share",
        "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1",
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ?feature=share",
        "https://www.youtube.com/v/dQw4w9WgXcQ",
        "  https://youtu.be/dQw4w9WgXcQ  \n",
        "Check this out! https://youtu.be/dQw4w9WgXcQ via @YouTube",
        "<https://www.youtube.com/watch?v=dQw4w9WgXcQ>",
        "dQw4w9WgXcQ",
    ])
    func extractsTheVideoID(link: String) throws {
        #expect(try YouTubeLink.videoID(from: link) == "dQw4w9WgXcQ")
    }

    @Test func keepsUnderscoresAndDashesInIDs() throws {
        #expect(try YouTubeLink.videoID(from: "https://youtu.be/a-b_c1234-_") == "a-b_c1234-_")
    }

    @Test(arguments: [
        "",
        "   ",
        "https://vimeo.com/123456",
        "https://example.com/watch?v=dQw4w9WgXcQ",
        "not a link at all",
        "https://youtube.example.com/watch?v=dQw4w9WgXcQ",
    ])
    func rejectsNonYouTubeInput(link: String) {
        #expect(throws: RecipeSourceError.notAYouTubeLink) { try YouTubeLink.videoID(from: link) }
    }

    @Test(arguments: [
        "https://www.youtube.com/",
        "https://www.youtube.com/@RickAstleyYT",
        "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
        "https://www.youtube.com/playlist?list=PL590L5WQmH8dpP0RyH5pCfIWRjMOJs-Q4",
        "https://www.youtube.com/watch?v=tooshort",
        "https://www.youtube.com/watch?list=PL123",
        "https://www.youtube.com/shorts/",
        "https://youtu.be/",
    ])
    func rejectsYouTubeLinksWithoutAVideo(link: String) {
        #expect(throws: RecipeSourceError.noVideoInLink) { try YouTubeLink.videoID(from: link) }
    }

    @Test func buildsWatchAndThumbnailURLs() {
        #expect(YouTubeLink.watchURL(for: "dQw4w9WgXcQ").absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(YouTubeLink.thumbnailURL(for: "dQw4w9WgXcQ").absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
    }

    @Test func errorsExplainWhatToDo() {
        #expect(RecipeSourceError.notAYouTubeLink.errorDescription?.contains("YouTube link") == true)
        #expect(RecipeSourceError.noVideoInLink.errorDescription?.contains("watch?v=") == true)
    }
}
