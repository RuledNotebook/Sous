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

    var body: some View {
        if session.phase == .ready, let recipe = session.recipe, let videoID = recipe.videoID {
            let collapsed = collapsible && video.isCollapsed
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Color.black
                        .overlay {
                            YouTubePlayerView(videoID: videoID, segment: segment(in: recipe),
                                              replay: session.videoReplays, command: video.command, controller: video)
                        }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: collapsed ? 112 : .infinity)
                        .clipShape(.rect(cornerRadius: collapsed ? 8 : 14))
                        .accessibilityLabel("Cooking video")

                    if collapsed {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stepLabel)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(video.isPlaying ? "Playing" : "Paused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        playPauseButton(iconOnly: true)
                        foldButton
                    }
                }

                if !collapsed {
                    HStack(spacing: 10) {
                        playPauseButton(iconOnly: false)
                        Button { session.repeatStep() } label: {
                            Label("Replay step", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .disabled(session.currentStep == nil)
                        .accessibilityLabel("Play this step's part of the video again")
                        Spacer(minLength: 0)
                        if let url = watchURL(in: recipe) {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Open in YouTube")
                        }
                        if collapsible { foldButton }
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.canvas)
            .animation(.snappy, value: collapsed)
            .animation(.snappy, value: video.isPlaying)
        }
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
