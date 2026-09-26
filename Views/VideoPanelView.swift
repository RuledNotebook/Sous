import Observation
import SwiftUI
import WebKit

/// The slice of the video a step covers: play from `start`, pause at `end` (where the next step begins).
nonisolated struct VideoSegment: Equatable, Sendable {
    var start: Int
    var end: Int?
}

/// A play or pause press. The serial makes each press distinct, even two "play"s in a row.
nonisolated struct PlaybackCommand: Equatable, Sendable {
    var serial: Int
    var play: Bool
}

/// What the cook has asked of the video, and what the player says it is doing.
/// Shared by the header (buttons), the details scroll (folds the header) and the player itself.
@Observable @MainActor
final class VideoController {
    /// Reported by the player page; the play/pause button follows this, not its own guess.
    private(set) var isPlaying = false
    private(set) var isReady = false
    private(set) var command = PlaybackCommand(serial: 0, play: true)
    /// The cook folded the video away, or pulled it back, by hand. nil means: follow the scroll.
    var manualCollapsed: Bool?
    /// True while the details are scrolled past the top.
    private(set) var detailsScrolled = false

    init() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "autoCollapseVideo") { manualCollapsed = true }
        #endif
    }

    var isCollapsed: Bool { manualCollapsed ?? detailsScrolled }

    func togglePlayback() { command = PlaybackCommand(serial: command.serial + 1, play: !isPlaying) }
    /// Play or pause on request (a voice command); a repeat of the same request still counts.
    func set(playing: Bool) { command = PlaybackCommand(serial: command.serial + 1, play: playing) }
    func toggleCollapsed() { manualCollapsed = !isCollapsed }

    /// Scrolling the details folds the header; scrolling back up unfolds it and forgets a manual choice.
    func detailsScrolled(_ down: Bool) {
        guard down != detailsScrolled else { return }
        detailsScrolled = down
        manualCollapsed = nil
    }

    /// YouTube player states: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued; -2 is our "ready".
    func playerReported(state: Int) {
        if state == -2 { isReady = true; return }
        isPlaying = state == 1 || state == 3
    }
}

/// YouTube's IFrame player in a web view. A new `segment` seeks and plays; nil pauses.
/// A new `command` plays or pauses in place. State changes come back through `controller`.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let segment: VideoSegment?
    /// Any change plays `segment` again from its start ("repeat").
    var replay = 0
    /// Any change moves the player by `seconds` and lets it run ("skip ahead ten seconds").
    var skip = VideoSkip(serial: 0, seconds: 0)
    var command = PlaybackCommand(serial: 0, play: true)
    var controller: VideoController?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(MessageProxy(coordinator), name: "cook")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.navigationDelegate = coordinator
        coordinator.controller = controller
        coordinator.load(videoID, into: web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.controller = controller
        if coordinator.videoID != videoID { coordinator.load(videoID, into: web) }
        if coordinator.commandSerial != command.serial {
            coordinator.commandSerial = command.serial
            coordinator.run("cook({seek: null, stopAt: null, play: \(command.play), keepStop: true})", in: web)
        }
        if coordinator.skipSerial != skip.serial {
            coordinator.skipSerial = skip.serial
            // A skip leaves the step's stop point behind: the cook is steering the video now.
            coordinator.run("cook({seek: null, stopAt: null, skip: \(skip.seconds), play: true})", in: web)
        }
        guard !coordinator.sentFirstCommand || coordinator.segment != segment || coordinator.replay != replay else { return }
        coordinator.sentFirstCommand = true
        coordinator.segment = segment
        coordinator.replay = replay
        let script: String
        if let segment {
            script = "cook({seek: \(segment.start), stopAt: \(segment.end.map(String.init) ?? "null"), play: true})"
        } else {
            script = "cook({seek: null, stopAt: null, play: false})"
        }
        coordinator.run(script, in: web)
    }

    /// Keeps the page and the player's commands in step: commands sent before the page has loaded wait.
    final class Coordinator: NSObject, WKNavigationDelegate {
        var videoID = ""
        var segment: VideoSegment?
        var replay = 0
        var skipSerial = 0
        var commandSerial = 0
        var sentFirstCommand = false
        weak var controller: VideoController?
        private var loaded = false
        private var pending: [String] = []

        func load(_ id: String, into web: WKWebView) {
            videoID = id
            loaded = false
            sentFirstCommand = false
            // YouTube needs a real https referrer and an `origin` that matches it; about:blank or a youtube.com
            // base gives "unavailable" (errors 152/153). Any https origin of our own works.
            web.loadHTMLString(YouTubePlayerView.html(videoID: id), baseURL: URL(string: YouTubePlayerView.origin))
        }

        func run(_ script: String, in web: WKWebView) {
            if loaded {
                web.evaluateJavaScript(script)
            } else {
                pending.append(script)
            }
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            for script in pending { web.evaluateJavaScript(script) }
            pending.removeAll()
        }

        func playerReported(state: Int) {
            controller?.playerReported(state: state)
        }
    }

    /// The web view retains its message handlers; this stands between so the coordinator can go away.
    final class MessageProxy: NSObject, WKScriptMessageHandler {
        private weak var coordinator: Coordinator?
        init(_ coordinator: Coordinator) { self.coordinator = coordinator }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let state = (message.body as? NSNumber)?.intValue else { return }
            coordinator?.playerReported(state: state)
        }
    }

    static let origin = "https://cookalong.app"

    /// The player page. `cook(cmd)` queues until the player is ready; a small timer pauses at `stopAt`.
    /// Player state changes are posted back as numbers (see `VideoController.playerReported`).
    static func html(videoID: String) -> String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
        #player{position:absolute;top:0;left:0;width:100%;height:100%}</style></head>
        <body><div id="player"></div>
        <script>
        var player = null, ready = false, pending = null, stopAt = null;
        function post(state) { try { window.webkit.messageHandlers.cook.postMessage(state); } catch (e) {} }
        var tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            videoId: '\(videoID)',
            playerVars: { playsinline: 1, controls: 0, fs: 0, disablekb: 1, iv_load_policy: 3, rel: 0, modestbranding: 1, origin: '\(origin)' },
            events: {
              onReady: function () { ready = true; post(-2); if (pending) { apply(pending); pending = null; } },
              onStateChange: function (e) { post(e.data); }
            }
          });
        }
        function apply(cmd) {
          if (!cmd.keepStop) { stopAt = cmd.stopAt; }
          if (cmd.seek !== null && cmd.seek !== undefined) { player.seekTo(cmd.seek, true); }
          if (cmd.skip) { player.seekTo(Math.max(0, player.getCurrentTime() + cmd.skip), true); }
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
