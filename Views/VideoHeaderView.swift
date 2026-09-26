import SwiftUI

/// The video and its buttons, at the top of the details display. Full width while the cook is
/// at the top of the details; folds into one row (a small player, the step, play/pause, unfold)
/// once they scroll down to read, so the words get the screen. The player view keeps its
/// identity across both states, so playback never restarts when the header folds.
struct VideoHeaderView: View {
    @Environment(CookSession.self) private var session
    @Environment(VideoController.self) private var video
    /// False in the closed-pose sheet, where there is nothing to fold away for.
    var collapsible = true

    /// Width available to the expanded player, measured once; the web view is laid out at this size
    /// in both states and only scaled when folded, so WebKit never re-lays out mid-animation.
    @State private var expandedWidth: CGFloat = 0

    private static let miniSize = CGSize(width: 112, height: 63)

    var body: some View {
        if session.phase == .ready, let recipe = session.recipe, let videoID = recipe.videoID {
            let collapsed = collapsible && video.isCollapsed
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    playerStage(videoID: videoID, recipe: recipe, collapsed: collapsed)

                    if collapsed {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stepLabel)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(video.isPlaying ? "Playing" : "Paused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                        Spacer(minLength: 0)
                        playPauseButton(iconOnly: true)
                            .transition(.opacity)
                        foldButton
                            .transition(.opacity)
                    }
                }

                if !collapsed {
                    HStack(spacing: 10) {
                        playPauseButton(iconOnly: false)
                        Button { session.repeatStep() } label: {
                            Label("Replay step", systemImage: "arrow.counterclockwise")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.currentStep == nil)
                        .accessibilityLabel("Play this step's part of the video again")
                        Spacer(minLength: 0)
                        if let url = watchURL(in: recipe) {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Open in YouTube")
                        }
                        if collapsible { foldButton }
                    }
                    .font(.subheadline)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.canvas)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                let inner = max(width - 32, 1)
                if abs(inner - expandedWidth) > 0.5 { expandedWidth = inner }
            }
            .animation(.smooth(duration: 0.35), value: collapsed)
            .animation(.smooth(duration: 0.25), value: video.isPlaying)
            .onChange(of: session.videoPlayback) { _, request in
                if let request { video.set(playing: request.play) }   // "pause" / "play", said out loud
            }
        }
    }

    /// The player at its full size, scaled and clipped into the mini box when folded. Same view
    /// identity in both states, so playback carries on. While folded and paused, the video's own
    /// thumbnail covers YouTube's title bar and play button, which would otherwise fill the box.
    private func playerStage(videoID: String, recipe: Recipe, collapsed: Bool) -> some View {
        let full = CGSize(width: max(expandedWidth, 1), height: max(expandedWidth, 1) * 9 / 16)
        let mini = Self.miniSize
        let scale = collapsed ? mini.width / full.width : 1
        return ZStack(alignment: .topLeading) {
            Color.black
                .overlay {
                    YouTubePlayerView(videoID: videoID, segment: segment(in: recipe),
                                      replay: session.videoReplays, skip: session.videoSkip,
                                      command: video.command, controller: video)
                }
                .frame(width: full.width, height: full.height)
                .scaleEffect(scale, anchor: .topLeading)

            if collapsed, !video.isPlaying {
                Color.black
                    .overlay {
                        AsyncImage(url: recipe.thumbnailURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                        }
                    }
                    .overlay {
                        Image(systemName: "pause.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.45), in: .circle)
                    }
                    .frame(width: mini.width, height: mini.height)
                    .transition(.opacity)
            }
        }
        .frame(width: collapsed ? mini.width : full.width, height: collapsed ? mini.height : full.height, alignment: .topLeading)
        .clipShape(.rect(cornerRadius: collapsed ? 8 : 14))
        .accessibilityLabel("Cooking video")
    }

    private func playPauseButton(iconOnly: Bool) -> some View {
        Button { video.togglePlayback() } label: {
            Group {
                if iconOnly {
                    Image(systemName: video.isPlaying ? "pause.fill" : "play.fill")
                } else {
                    Label(video.isPlaying ? "Pause" : "Play", systemImage: video.isPlaying ? "pause.fill" : "play.fill")
                        .padding(.horizontal, 6)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.actionFill)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(video.isPlaying ? "Pause video" : "Play video")
    }

    private var foldButton: some View {
        Button { video.toggleCollapsed() } label: {
            Image(systemName: video.isCollapsed ? "chevron.down" : "chevron.up")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(video.isCollapsed ? "Show the video" : "Hide the video")
    }

    private var stepLabel: String {
        switch session.slide {
        case .overview: "Ingredients"
        case .step(let index): "Step \(index + 1) of \(session.steps.count)"
        case .done: "Done"
        }
    }

    private func segment(in recipe: Recipe) -> VideoSegment? {
        guard case .step(let index) = session.slide, recipe.steps.indices.contains(index) else { return nil }
        let steps = recipe.steps
        let start = steps[index].startSecond
        let next = index + 1 < steps.count ? steps[index + 1].startSecond : nil
        return VideoSegment(start: start, end: next.flatMap { $0 > start ? $0 : nil })
    }

    private func watchURL(in recipe: Recipe) -> URL? {
        if let step = session.currentStep { return recipe.watchURL(for: step) }
        return recipe.sourceURL
    }
}
