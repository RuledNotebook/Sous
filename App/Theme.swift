import SwiftUI

/// Kitchen palette: basil for progress, butter for "something is cooking right now".
enum Theme {
    static let basil    = Color(red: 0.243, green: 0.486, blue: 0.310)  // #3E7C4F
    static let butter   = Color(red: 0.949, green: 0.757, blue: 0.306)  // #F2C14E
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
