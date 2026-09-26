import Foundation

/// Spellings automatic captions get wrong for common cooking words. Applied to step text and
/// ingredient names after extraction; the model is also told captions mis-hear, but a small
/// model repeats what it read.
nonisolated enum CaptionFixes {
    static let replacements: [(heard: String, meant: String)] = [
        ("gacha jang", "gochujang"), ("gcha jang", "gochujang"), ("gotcha jang", "gochujang"), ("gochu jang", "gochujang"), ("kochujang", "gochujang"),
        ("go chu jang", "gochujang"), ("dwenjang", "doenjang"), ("den jang", "doenjang"),
        ("the walk", "the wok"), ("a walk", "a wok"), ("my walk", "my wok"), ("your walk", "your wok"),
        ("heat walk", "heat wok"), ("hot walk", "hot wok"), ("walk heating", "wok heating"), ("in walk", "in wok"),
        ("sriracha sauce", "sriracha"), ("sir racha", "sriracha"), ("miran", "mirin"), ("mirren", "mirin"),
        ("tumeric", "turmeric"), ("expresso", "espresso"), ("worcester sauce", "worcestershire sauce"),
        ("chipotle", "chipotle"), ("bock choy", "bok choy"), ("bok choi", "bok choy"), ("pak choy", "pak choi"),
        ("tahiti", "tahini"), ("ghi", "ghee"), ("sesame oil", "sesame oil"),
    ]

    static func apply(to text: String) -> String {
        var out = text
        for (heard, meant) in replacements where heard != meant {
            out = out.replacingOccurrences(of: heard, with: meant, options: [.caseInsensitive])
        }
        return out
    }
}
