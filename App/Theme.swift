import SwiftUI

/// System surfaces and type adapt to appearance and accessibility settings.
/// Green marks actions and progress; amber is reserved for an active timer.
enum Theme {
    static let accent   = Color.accentColor
    static let actionFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.42, blue: 0.28, alpha: 1)
            : UIColor(red: 0.15, green: 0.39, blue: 0.24, alpha: 1)
    })
    static let timer = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.77, blue: 0.43, alpha: 1)
            : UIColor(red: 0.65, green: 0.38, blue: 0.04, alpha: 1)
    })
    static let castIron = Color(red: 0.133, green: 0.149, blue: 0.165)  // #22262A
    static let card     = Color(.secondarySystemBackground)
    static let canvas   = Color(.systemBackground)
}

extension Int {
    /// 95 -> "1 h 35 min", 20 -> "20 min"
    var cookTime: String {
        guard self >= 60 else { return "\(self) min" }
        let h = self / 60, m = self % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
