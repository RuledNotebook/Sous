import SwiftUI
import WebKit

/// The slice of the video a step covers: play from `start`, pause at `end` (where the next step begins).
nonisolated struct VideoSegment: Equatable, Sendable {
    var start: Int
    var end: Int?
}

/// The YouTube video, wide, following the slideshow: every step slide jumps the video to the moment
/// the cook says it and pauses where the next step starts. Nothing shows until a recipe with a video is on.
struct VideoPanelView: View {
    @Environment(CookSession.self) private var session
    /// Fill whatever box the layout gives (the player letterboxes inside it); false keeps a 16:9 strip.
    var fill = false

    var body: some View {
        if session.phase == .ready, let recipe = session.recipe, let videoID = recipe.videoID {
            let player = Color.black
                .overlay { YouTubePlayerView(videoID: videoID, segment: segment(in: recipe), replay: session.videoReplays) }
                .clipShape(.rect(cornerRadius: 14))
                .accessibilityLabel("Cooking video")
            if fill {
                player
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                player
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }
        }
    }

    private func segment(in recipe: Recipe) -> VideoSegment? {
        guard case .step(let index) = session.slide, recipe.steps.indices.contains(index) else { return nil }
        let steps = recipe.steps
        let start = steps[index].startSecond
        let next = index + 1 < steps.count ? steps[index + 1].startSecond : nil
        return VideoSegment(start: start, end: next.flatMap { $0 > start ? $0 : nil })
    }
}

/// YouTube's IFrame player in a web view. A new `segment` seeks and plays; nil pauses.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let segment: VideoSegment?
    /// Any change plays `segment` again from its start ("repeat").
    var replay = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.navigationDelegate = context.coordinator
        context.coordinator.load(videoID, into: web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.videoID != videoID { coordinator.load(videoID, into: web) }
        guard !coordinator.sentFirstCommand || coordinator.segment != segment || coordinator.replay != replay else { return }
        coordinator.sentFirstCommand = true
        coordinator.segment = segment
        coordinator.replay = replay
        let command: String
        if let segment {
            command = "cook({seek: \(segment.start), stopAt: \(segment.end.map(String.init) ?? "null"), play: true})"
        } else {
            command = "cook({seek: null, stopAt: null, play: false})"
        }
        coordinator.run(command, in: web)
    }

    /// Keeps the page and the player's commands in step: commands sent before the page has loaded wait.
    final class Coordinator: NSObject, WKNavigationDelegate {
        var videoID = ""
        var segment: VideoSegment?
        var replay = 0
        var sentFirstCommand = false
        private var loaded = false
        private var pending: String?

        func load(_ id: String, into web: WKWebView) {
            videoID = id
            loaded = false
            sentFirstCommand = false
            // YouTube needs a real https referrer and an `origin` that matches it; about:blank or a youtube.com
            // base gives "unavailable" (errors 152/153). Any https origin of our own works.
            web.loadHTMLString(YouTubePlayerView.html(videoID: id), baseURL: URL(string: YouTubePlayerView.origin))
        }

        func run(_ command: String, in web: WKWebView) {
            if loaded {
                web.evaluateJavaScript(command)
            } else {
                pending = command
            }
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let pending {
                self.pending = nil
                web.evaluateJavaScript(pending)
            }
        }
    }

    static let origin = "https://cookalong.app"

    /// The player page. `cook(cmd)` queues until the player is ready; a small timer pauses at `stopAt`.
    static func html(videoID: String) -> String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
        #player{position:absolute;top:0;left:0;width:100%;height:100%}</style></head>
        <body><div id="player"></div>
        <script>
        var player = null, ready = false, pending = null, stopAt = null;
        var tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            videoId: '\(videoID)',
            playerVars: { playsinline: 1, controls: 1, rel: 0, modestbranding: 1, origin: '\(origin)' },
            events: { onReady: function () { ready = true; if (pending) { apply(pending); pending = null; } } }
          });
        }
        function apply(cmd) {
          stopAt = cmd.stopAt;
          if (cmd.seek !== null && cmd.seek !== undefined) { player.seekTo(cmd.seek, true); }
          if (cmd.play) { player.playVideo(); } else { player.pauseVideo(); }
        }
        function cook(cmd) { if (ready) { apply(cmd); } else { pending = cmd; } }
        setInterval(function () {
          if (ready && stopAt !== null && player.getPlayerState() === 1 && player.getCurrentTime() >= stopAt - 0.25) {
            player.pauseVideo();
            stopAt = null;
          }
        }, 250);
        </script></body></html>
        """
    }
}
