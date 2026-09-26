#if DEBUG
import SwiftUI

extension CookSession {
    /// A session already showing `Recipe.demo`, for previews and the layout lab.
    /// Uses the stubs, so no model, microphone or network is involved.
    static func preview(slide: Slide = .step(2), timerRunning: Bool = false, checked: Int = 3) -> CookSession {
        let session = CookSession.live()
        session.show(.demo)
        for index in 0..<min(checked, Recipe.demo.ingredients.count) { session.toggleIngredient(index) }
        session.go(to: slide)
        if timerRunning { session.startTimer() }
        return session
    }
}

// iPhone Duo poses. Sizes are the display's point sizes; RootView only ever sees its container.

#Preview("Closed · 466×678", traits: .fixedLayout(width: 466, height: 678)) {
    RootView().environment(CookSession.preview())
}

#Preview("Open · 951×669", traits: .fixedLayout(width: 951, height: 669)) {
    RootView().environment(CookSession.preview(slide: .step(3), timerRunning: true))
}

#Preview("Open, rotated · 669×951", traits: .fixedLayout(width: 669, height: 951)) {
    RootView().environment(CookSession.preview())
}

#Preview("Ingredients · 951×669", traits: .fixedLayout(width: 951, height: 669)) {
    RootView().environment(CookSession.preview(slide: .overview))
}

#Preview("Done · 466×678", traits: .fixedLayout(width: 466, height: 678)) {
    RootView().environment(CookSession.preview(slide: .done, checked: 8))
}

#Preview("Empty · 466×678", traits: .fixedLayout(width: 466, height: 678)) {
    RootView().environment(CookSession.live())
}

#Preview("Closed · XXL type", traits: .fixedLayout(width: 466, height: 678)) {
    RootView().environment(CookSession.preview(slide: .step(3), timerRunning: true))
        .dynamicTypeSize(.xxxLarge)
}
#endif
