import SwiftUI

/// Adapts to the container, never to UIScreen (on iPhone Duo, UIScreen.main
/// reports the outer display even while the app runs on the inner one).
///
///  Tall (closed 466x678, or open and rotated 669x951)     Wide (open 951x669)
///  ┌───────────────┐                                      ┌─────────────┬─────────────┐
///  │  video (16:9) │                                      │ video (16:9)│             │
///  ├───────────────┤                                      ├─────────────┤  slideshow  │
///  │   slideshow   │                                      │   details   │             │
///  ├───────────────┤                                      │  (scrolls)  │             │
///  │    details    │                                      └────────── hinge ──────────┘
///  └───────────────┘
///
/// The video sits on top, full width, and follows the slides. Wide containers still split
/// 50/50 on the physical centre line so the seam lands on the hinge; tall ones give the
/// slideshow the room it needs and let the details scroll in what is left.
struct RootView: View {
    var body: some View {
        GeometryReader { geo in
            let plan = LayoutPlan(safeAreaSize: geo.size, insets: geo.safeAreaInsets)
            Group {
                if plan.isWide {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            VideoPanelView()
                            DetailsPanelView()
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: plan.leadingPanelLength)
                        .overlay(alignment: .trailing) { Seam(.vertical) }
                        SlideshowView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        VideoPanelView()
                        SlideshowView()
                            .frame(height: plan.slideshowHeight)
                            .overlay(alignment: .bottom) { Seam(.horizontal) }
                        DetailsPanelView()
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .animation(.snappy, value: plan.isWide)
        }
        .background(Theme.canvas)
        .fontDesign(.rounded)
        .tint(Theme.basil)
    }
}

/// What the layout needs, computed once per container size.
struct LayoutPlan: Equatable {
    let isWide: Bool
    /// Full display size, safe-area insets included.
    let size: CGSize
    /// Width (wide) or height (tall) of the leading panel inside the safe area,
    /// chosen so the seam sits on the physical centre line.
    let leadingPanelLength: CGFloat
    /// Tall pose: the slideshow's height under the video, leaving the details room to scroll.
    let slideshowHeight: CGFloat

    init(safeAreaSize: CGSize, insets: EdgeInsets) {
        size = CGSize(width: safeAreaSize.width + insets.leading + insets.trailing,
                      height: safeAreaSize.height + insets.top + insets.bottom)
        isWide = size.width > size.height
        leadingPanelLength = isWide ? size.width / 2 - insets.leading : size.height / 2 - insets.top
        let videoHeight = safeAreaSize.width * 9 / 16 + 12
        slideshowHeight = max(240, (safeAreaSize.height - videoHeight) * 0.5)
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
