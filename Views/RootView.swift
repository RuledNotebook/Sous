import SwiftUI

/// Adapts to the container, never to UIScreen (on iPhone Duo, UIScreen.main
/// reports the outer display even while the app runs on the inner one).
///
///  Closed (466x678)          Open, rotated (669x951)       Open (951x669)
///  ┌───────────────┐         ┌───────────────┐             ┌─────────────┬─────────────┐
///  │ cooking detail│         │    details    │             │   details   │  slideshow  │
///  │   (scrolls)   │         ├──── hinge ────┤             └────────── hinge ──────────┘
///  │   controls    │         │   slideshow   │
///  └───────────────┘         └───────────────┘
/// The inner display splits at its physical centre. The outer display has no hinge,
/// so the instructions get the full height and navigation stays at the bottom.
struct RootView: View {
    @Environment(CookSession.self) private var session

    var body: some View {
        GeometryReader { geo in
            let plan = LayoutPlan(safeAreaSize: geo.size, insets: geo.safeAreaInsets)
            Group {
                if !plan.usesTwoPanels {
                    VStack(spacing: 0) {
                        DetailsPanelView(compact: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if session.phase == .ready {
                            SlideshowBar(compact: true)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Theme.card)
                        }
                    }
                } else if plan.isWide {
                    HStack(spacing: 0) {
                        DetailsPanelView()
                            .frame(width: plan.leadingPanelLength)
                            .overlay(alignment: .trailing) { Seam(.vertical) }
                        SlideshowView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        DetailsPanelView()
                            .frame(height: plan.leadingPanelLength)
                            .overlay(alignment: .bottom) { Seam(.horizontal) }
                        SlideshowView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .animation(.snappy, value: plan.usesTwoPanels)
        }
        .background(Theme.canvas)
        .tint(Theme.accent)
    }
}

/// What the layout needs, computed once per container size.
struct LayoutPlan: Equatable {
    let isWide: Bool
    let usesTwoPanels: Bool
    /// Full display size, safe-area insets included.
    let size: CGSize
    /// Width (wide) or height (tall) of the details panel inside the safe area,
    /// chosen so the seam sits on the physical centre line.
    let leadingPanelLength: CGFloat

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
