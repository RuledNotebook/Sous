#if DEBUG
import SwiftUI

/// Debug-only launch arguments, handy for screenshots from `xcrun simctl launch`:
///
///   -layoutLab 466x678     render RootView inside a fixed 466×678 pt frame (any WxH works)
///   -autoDemo YES          load the demo recipe on launch, as if Demo were tapped
///   -autoDemoSlide 3       then jump to slide 3 (0 = ingredients, 1…n = steps, n+1 = done)
///   -autoDemoTimer YES     then start the step timer
///
/// Combine with Apple's own `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXL`
/// to check Dynamic Type, and COOKALONG_SECONDS_PER_MINUTE=1 in the environment for fast timers.
/// Nothing here ships: the whole file is `#if DEBUG`.
struct DebugLaunchOptions: ViewModifier {
    let session: CookSession
    private let defaults = UserDefaults.standard

    func body(content: Content) -> some View {
        Group {
            if let size = labSize {
                // Pinned near the top so system alerts (centred on screen) don't hide the slides.
                ZStack(alignment: .top) {
                    Color(white: 0.5).ignoresSafeArea()
                    content
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .border(.black, width: 1)
                        .padding(.top, 40)
                }
            } else {
                content
            }
        }
        .task {
            guard defaults.bool(forKey: "autoDemo") else { return }
            await session.loadDemo()
            if let index = integer(forKey: "autoDemoSlide"), session.slides.indices.contains(index) {
                session.go(to: session.slides[index])
            }
            if defaults.bool(forKey: "autoDemoTimer") { session.startTimer() }
        }
    }

    private var labSize: CGSize? {
        guard let spec = defaults.string(forKey: "layoutLab") else { return nil }
        let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }

    /// Launch arguments arrive as strings or numbers depending on how they were typed.
    private func integer(forKey key: String) -> Int? {
        if let number = defaults.object(forKey: key) as? Int { return number }
        return defaults.string(forKey: key).flatMap { Int($0) }
    }
}
#endif
