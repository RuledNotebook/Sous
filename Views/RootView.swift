import SwiftUI

/// Adapts to the container, never to UIScreen (on iPhone Duo, UIScreen.main
/// reports the outer display even while the app runs on the inner one).
///
/// Closed: one cooking panel with a video sheet. Open: the video (folding away when the
/// cook scrolls to read) sits over the details on one side of the hinge, the slideshow on
/// the other: the left half when wide, the upper display when tall.
struct RootView: View {
    @Environment(CookSession.self) private var session
    @State private var showVideo = false
    @State private var video = VideoController()

    var body: some View {
        GeometryReader { geo in
            let plan = LayoutPlan(safeAreaSize: geo.size, insets: geo.safeAreaInsets)
            Group {
                if !plan.usesTwoPanels {
                    VStack(spacing: 0) {
                        DetailsPanelView(compact: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if session.phase == .ready {
                            SlideshowBar(compact: true, onShowVideo: { showVideo = true })
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Theme.card)
                        }
                    }
                } else if plan.isWide {
                    HStack(spacing: 0) {
                        leadingPanel(maxVideoHeight: nil)
                            .padding(.trailing, plan.hingeInset)
                            .frame(width: plan.leadingPanelLength)
                            .overlay(alignment: .trailing) { Seam(.vertical) }
                        SlideshowView()
                            .padding(.leading, plan.hingeInset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        leadingPanel(maxVideoHeight: plan.leadingPanelLength - plan.hingeInset)
                            .padding(.bottom, plan.hingeInset)
                            .frame(height: plan.leadingPanelLength)
                            .overlay(alignment: .bottom) { Seam(.horizontal) }
                        SlideshowView()
                            .padding(.top, plan.hingeInset)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .environment(video)
            .animation(.snappy, value: plan.usesTwoPanels)
            .onChange(of: session.videoReplays) { _, _ in
                if !plan.usesTwoPanels { showVideo = true }
            }
            .onChange(of: session.videoSkip) { _, _ in
                if !plan.usesTwoPanels { showVideo = true }   // steering the video by voice brings it up
            }
        }
        .background(Theme.canvas)
        .tint(Theme.accent)
        .sheet(isPresented: $showVideo) {
            VideoHeaderView(collapsible: false)
                .environment(video)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    /// Video (folding) over the details: the whole upper display when open and tall, the left half when wide.
    private func leadingPanel(maxVideoHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            // Sized first, so the player gets the full width and the details take what's left.
            VideoHeaderView(maxHeight: maxVideoHeight)
                .layoutPriority(1)
            DetailsPanelView()
                .frame(maxHeight: .infinity)
        }
    }
}

/// What the layout needs, computed once per container size.
struct LayoutPlan: Equatable {
    let isWide: Bool
    let usesTwoPanels: Bool
    /// Full display size, safe-area insets included.
    let size: CGSize
    /// Width (wide) or height (tall) of the leading panel inside the safe area,
    /// chosen so the seam sits on the physical centre line.
    let leadingPanelLength: CGFloat
    /// Points kept clear on each side of the fold, where the two displays' edges hide content
    /// (`UIHinge` reports only the angle, not where the hinge is). Buttons never sit inside it.
    let hingeInset: CGFloat = 24

    init(safeAreaSize: CGSize, insets: EdgeInsets) {
        size = CGSize(width: safeAreaSize.width + insets.leading + insets.trailing,
                      height: safeAreaSize.height + insets.top + insets.bottom)
        isWide = size.width > size.height
        usesTwoPanels = min(size.width, size.height) >= 600
        leadingPanelLength = isWide ? size.width / 2 - insets.leading : size.height / 2 - insets.top
    }
}

/// Hairline between the panels. Sits on the seam so it disappears into the hinge.
private struct Seam: View {
    let axis: Axis
    init(_ axis: Axis) { self.axis = axis }

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
            .accessibilityHidden(true)
    }
}
