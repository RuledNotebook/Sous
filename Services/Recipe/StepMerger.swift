import Foundation

/// A step as extracted from one transcript window, before merging. Model-agnostic so the
/// on-device and cloud analyzers share the same post-processing.
nonisolated struct StepCandidate: Hashable, Sendable {
    var title: String
    var instruction: String
    var startSecond: Double
    var minutes: Int
    var isHandsOn: Bool
    var needsTimer: Bool
    var tip: String = ""
    var imagePrompt: String = ""
    var vessel: String = ""
    var items: [String] = []

    // Provenance, used by the merge pass to pick the better of two duplicates.
    var windowIndex: Int = 0
    var windowStart: Double = 0
    var windowEnd: Double = .infinity
    /// Position within its window's output.
    var order: Int = 0

    /// Seconds between this step and the nearest edge of the window that produced it. A step deep
    /// inside a window was extracted with context on both sides, so it wins over an edge copy.
    var edgeDistance: Double {
        min(startSecond - windowStart, windowEnd - startSecond)
    }
}

// MARK: - Merge pass

/// Dedupes and orders step candidates gathered from overlapping windows.
nonisolated enum StepMerger {
    struct Options: Sendable {
        /// Two candidates closer than this (seconds) with similar text are the same step.
        var timeTolerance: Double = 20
        /// Jaccard similarity of content words (title + instruction) above which text counts as similar.
        var similarityThreshold: Double = 0.3
        /// Candidates with the same normalised title within this many seconds are the same step.
        var titleTimeTolerance: Double = 60
        init() {}
    }

    static func merge(_ candidates: [StepCandidate], options: Options = Options()) -> [StepCandidate] {
        let sorted = candidates.sorted { a, b in
            if a.startSecond != b.startSecond { return a.startSecond < b.startSecond }
            if a.windowStart != b.windowStart { return a.windowStart < b.windowStart }
            return a.order < b.order
        }
        var merged: [StepCandidate] = []
        for candidate in sorted {
            // Only recent steps can be duplicates; scan back until we're outside the time tolerance.
            var match: Int?
            for i in stride(from: merged.count - 1, through: 0, by: -1) {
                if candidate.startSecond - merged[i].startSecond > max(options.timeTolerance, options.titleTimeTolerance) { break }
                if isDuplicate(merged[i], candidate, options: options) { match = i; break }
            }
            if let match {
                merged[match] = combine(merged[match], candidate)
            } else {
                merged.append(candidate)
            }
        }
        return merged
    }

    static func isDuplicate(_ a: StepCandidate, _ b: StepCandidate, options: Options = Options()) -> Bool {
        let dt = abs(a.startSecond - b.startSecond)
        let sameWindow = a.windowIndex == b.windowIndex && a.windowStart == b.windowStart
        if sameWindow {
            // The model chose to emit both; only collapse an exact repeat.
            return dt == 0 && normalizedTitle(a.title) == normalizedTitle(b.title)
        }
        if normalizedTitle(a.title) == normalizedTitle(b.title), dt <= options.titleTimeTolerance { return true }
        guard dt <= options.timeTolerance else { return false }
        return similarity(a, b) >= options.similarityThreshold
    }

    /// Jaccard similarity over stemmed content words of title + instruction.
    static func similarity(_ a: StepCandidate, _ b: StepCandidate) -> Double {
        let wa = contentWords(a.title + " " + a.instruction)
        let wb = contentWords(b.title + " " + b.instruction)
        guard !wa.isEmpty, !wb.isEmpty else { return 0 }
        let inter = Double(wa.intersection(wb).count)
        let union = Double(wa.union(wb).count)
        return union == 0 ? 0 : inter / union
    }

    /// The surviving step when two candidates describe the same action.
    static func combine(_ kept: StepCandidate, _ new: StepCandidate) -> StepCandidate {
        let (winner, loser) = new.edgeDistance > kept.edgeDistance ? (new, kept) : (kept, new)
        var out = winner
        if out.tip.isEmpty { out.tip = loser.tip }
        if out.imagePrompt.isEmpty { out.imagePrompt = loser.imagePrompt }
        if out.instruction.count < loser.instruction.count / 2 { out.instruction = loser.instruction }
        // Small models under-estimate waits far more often than they over-estimate them.
        out.minutes = max(out.minutes, loser.minutes)
        out.needsTimer = out.needsTimer || loser.needsTimer
        out.isHandsOn = out.isHandsOn && loser.isHandsOn
        return out
    }

    // MARK: Text helpers

    static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "then", "to", "of", "in", "into", "on", "onto", "with", "it",
        "its", "them", "this", "that", "for", "your", "you", "some", "until", "till", "is", "are",
        "be", "at", "as", "so", "up", "off", "out", "over", "about", "just", "now", "well", "all",
    ]

    static func normalizedTitle(_ title: String) -> String {
        contentWords(title).sorted().joined(separator: " ")
    }

    static func contentWords(_ text: String) -> Set<String> {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " }
        var out: Set<String> = []
        for raw in String(cleaned).split(separator: " ") {
            let word = String(raw)
            guard word.count > 1, !stopWords.contains(word) else { continue }
            out.insert(stem(word))
        }
        return out
    }

    /// Crude suffix stripping so "slice", "slices", "slicing" and "sliced" all become "slic".
    static func stem(_ word: String) -> String {
        var w = word
        for suffix in ["ing", "ies", "ed", "es", "ly", "s"] where w.count > suffix.count + 3 && w.hasSuffix(suffix) {
            w.removeLast(suffix.count)
            if suffix == "ies" { w += "y" }
            // "chopped" -> "chopp" -> "chop"; keep "ss" and "ll" ("toss", "grill").
            if suffix == "ed" || suffix == "ing", w.count > 3,
               let last = w.last, last == w[w.index(w.endIndex, offsetBy: -2)], !"sl".contains(last) {
                w.removeLast()
            }
            break
        }
        if w.count > 3, w.hasSuffix("e") { w.removeLast() }
        return w
    }
}

// MARK: - Timestamps

/// Keeps step start times inside the video and strictly increasing.
nonisolated enum TimestampClamper {
    /// Clamps every start into `0...(videoDuration - 1)` and spaces them at least `minimumGap`
    /// seconds apart without pushing the last step past the end of the video. When more steps
    /// than seconds exist the gap shrinks so everything still fits. A non-positive duration means
    /// "unknown": starts are only floored at zero and made increasing.
    static func clamp(_ starts: [Double], videoDuration: Double, minimumGap: Double = 1) -> [Double] {
        guard !starts.isEmpty else { return [] }
        let known = videoDuration > 0
        let upper = known ? max(videoDuration - 1, 0) : Double.infinity
        var gap = minimumGap
        if known, starts.count > 1 { gap = min(gap, upper / Double(starts.count - 1)) }

        var out = starts.map { s -> Double in
            let v = s.isFinite ? s : 0
            return min(max(v, 0), upper)
        }
        for i in out.indices.dropFirst() where out[i] < out[i - 1] + gap {
            out[i] = out[i - 1] + gap
        }
        if known {
            out[out.count - 1] = min(out[out.count - 1], upper)
            for i in stride(from: out.count - 2, through: 0, by: -1) where out[i] > out[i + 1] - gap {
                out[i] = max(out[i + 1] - gap, 0)
            }
        }
        return out
    }
}

// MARK: - Minutes

/// Turns a model's minute estimate into realistic kitchen time.
///
/// Videos jump-cut over waiting, so a small model that reads "[140s] into the oven for 25 minutes"
/// followed by "[143s] and it's done" tends to answer `1`. A spoken duration always wins here.
/// Without one, the verb in the step title sets a floor a home cook would recognise, and the
/// model's guess is capped (small models also say "15 minutes" for tossing pasta).
nonisolated enum MinutesEstimator {
    static let maximumMinutes = 24 * 60
    /// Longest plausible unspoken hands-on step (a big chop, kneading); longer ones get said out loud.
    static let handsOnCap = 8
    /// Longest plausible unspoken wait (a dough rise); anything longer is normally said out loud.
    static let waitingCap = 180

    static func minutes(model: Int, title: String, instruction: String, isHandsOn: Bool = true) -> Int {
        if let explicit = explicitMinutes(in: title + ". " + instruction) {
            return clamp(explicit)
        }
        // Floors come from the title only: "rest of the butter" in an instruction is not a rest.
        let floor = passiveFloor(for: title)
        // A long unspoken wait must be a recognisable one (bake, simmer, rest); "Serve, 15 min" is a guess.
        let isWait = !isHandsOn && floor > 1
        let cap = isWait ? waitingCap : handsOnCap
        return clamp(max(min(model, cap), floor))
    }

    static func needsTimer(model: Bool, title: String, instruction: String) -> Bool {
        model || (explicitMinutes(in: title + ". " + instruction) ?? 0) >= 1
    }

    static func clamp(_ minutes: Int) -> Int { min(max(minutes, 1), maximumMinutes) }

    /// Sum of the durations spoken in `text`, in whole minutes (rounded up), or nil when none.
    /// Handles digits and number words, ranges ("20-25", "20 to 25": upper bound), "and a half",
    /// "per side" (doubled), seconds, minutes, hours and "overnight".
    static func explicitMinutes(in text: String) -> Int? {
        let lower = text.lowercased()
            .replacingOccurrences(of: "½", with: " 0.5 ")
            .replacingOccurrences(of: "¼", with: " 0.25 ")
            .replacingOccurrences(of: "–", with: "-")
        var total = 0.0
        var found = false
        for m in durationRegex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            func group(_ i: Int) -> String? {
                guard let r = Range(m.range(at: i), in: lower) else { return nil }
                return String(lower[r])
            }
            guard var value = number(group(1)) else { continue }
            if let upper = number(group(2)) ?? number(group(5)) { value = max(value, upper) }
            if group(3) != nil || group(6) != nil { value += 0.5 }
            guard let unit = group(4) else { continue }
            var minutes = value * unitMinutes(unit)
            if group(7) != nil { minutes *= 2 }
            total += minutes
            found = true
        }
        if lower.contains("overnight") { total += 8 * 60; found = true }
        guard found, total > 0 else { return nil }
        return Int(total.rounded(.up))
    }

    /// Minimum realistic minutes implied by the verbs in the text; 1 when nothing passive is mentioned.
    static func passiveFloor(for text: String) -> Int {
        let words = StepMerger.contentWords(text)
        var floor = 1
        for (keywords, minutes) in floors where !words.isDisjoint(with: keywords) {
            floor = max(floor, minutes)
        }
        return floor
    }

    // MARK: Internals

    private static let floors: [(Set<String>, Int)] = [
        (["freeze"], 60),
        (["marinate", "chill", "refrigerate", "rise", "proof", "prove", "soak", "brine"], 30),
        (["bake", "roast"], 20),
        (["simmer", "braise", "stew", "caramelize", "caramelise", "rest", "cool"], 15),
        (["preheat"], 10),
        (["boil", "reduce", "steam", "knead", "poach"], 8),
        (["grill", "broil"], 6),
        (["fry", "fried", "sauté", "saute", "sear", "brown", "toast", "chop", "dice", "slice", "mince", "peel", "grate"], 3),
    ].map { (Set($0.0.map(StepMerger.stem)), $0.1) }

    private static let numberWord =
        #"(?:\d+(?:[.,]\d+)?|half an|half a|quarter of an|a couple of|a few|several|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|twenty(?:[ -]five)?|thirty(?:[ -]five)?|forty(?:[ -]five)?|fifty|sixty|ninety)"#

    /// Groups: 1 number, 2 upper bound ("20 to 25 minutes"), 3 "and a half" before the unit, 4 unit,
    /// 5 upper bound after the unit ("a minute or two"), 6 "and a half" after the unit, 7 "per side".
    private static let durationRegex: NSRegularExpression = {
        let pattern = #"\b("# + numberWord + #")(?:\s*(?:to|or|-)\s*("# + numberWord + #"))?"#
            + #"(\s+and\s+a\s+half)?\s*(?:more\s+)?(seconds?|secs?|minutes?|mins?|hours?|hrs?)\b"#
            + #"(?:\s+or\s+("# + numberWord + #"))?(\s+and\s+a\s+half)?(\s+(?:per|on\s+each|each|a)\s+side)?"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func number(_ s: String?) -> Double? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let d = Double(s.replacingOccurrences(of: ",", with: ".")) { return d }
        switch s {
        case "a", "an", "one": return 1
        case "a couple of", "two": return 2
        case "a few", "three": return 3
        case "several": return 5
        case "half an", "half a": return 0.5
        case "quarter of an": return 0.25
        case "four": return 4
        case "five": return 5
        case "six": return 6
        case "seven": return 7
        case "eight": return 8
        case "nine": return 9
        case "ten": return 10
        case "eleven": return 11
        case "twelve": return 12
        case "thirteen": return 13
        case "fourteen": return 14
        case "fifteen": return 15
        case "twenty": return 20
        case "twenty five", "twenty-five": return 25
        case "thirty": return 30
        case "thirty five", "thirty-five": return 35
        case "forty": return 40
        case "forty five", "forty-five": return 45
        case "fifty": return 50
        case "sixty": return 60
        case "ninety": return 90
        default: return nil
        }
    }

    private static func unitMinutes(_ unit: String) -> Double {
        if unit.hasPrefix("s") { return 1.0 / 60 }
        if unit.hasPrefix("h") { return 60 }
        return 1
    }
}
