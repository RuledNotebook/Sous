import Foundation

/// Spoken forms of each command and word-level matching, so "backyard" isn't "back".
///
/// A pattern is a list of words; `#` stands for a number ("ten", "10") that may be followed by
/// "seconds" or "minutes". The earliest phrase in what was heard wins, and at the same spot the
/// longer one does, so "go back ten seconds" moves the video while "go back" is the previous step.
nonisolated enum CommandMatcher {
    struct Rule {
        let pattern: [String]
        let make: (Int?) -> VoiceCommand
    }

    static let defaultSkip = 10

    /// Pattern words, keeping the `#` slot (the tokenizer would strip it).
    static func pattern(_ phrase: String) -> [String] {
        phrase.lowercased().split(separator: " ").map(String.init)
    }

    static let rules: [Rule] = {
        func fixed(_ command: VoiceCommand, _ phrases: String...) -> [Rule] {
            phrases.map { Rule(pattern: pattern($0), make: { _ in command }) }
        }
        func ahead(_ phrases: String...) -> [Rule] {
            phrases.map { Rule(pattern: pattern($0), make: { .skip(seconds: $0 ?? defaultSkip) }) }
        }
        func back(_ phrases: String...) -> [Rule] {
            phrases.map { Rule(pattern: pattern($0), make: { .skip(seconds: -($0 ?? defaultSkip)) }) }
        }
        func step(_ phrases: String...) -> [Rule] {
            phrases.map { Rule(pattern: pattern($0), make: { .goToStep($0 ?? 1) }) }
        }
        var rules: [Rule] = []
        rules += fixed(.next, "next step", "go forward", "next", "continue", "forward")
        rules += fixed(.back, "previous step", "go back", "previous", "back", "last step")
        rules += fixed(.repeatStep, "say again", "play that again", "replay step", "repeat", "again", "replay")
        rules += fixed(.startTimer, "start the timer", "start a timer", "set the timer", "set a timer", "start timer", "set timer")
        rules += fixed(.stopTimer, "stop the timer", "cancel the timer", "dismiss the timer", "stop timer", "cancel timer", "dismiss timer")
        // Video timeline. With a number: "skip ahead ten seconds", "go back thirty seconds", "forward two minutes".
        rules += ahead("skip ahead #", "skip forward #", "fast forward #", "go forward #", "jump ahead #", "forward #", "ahead #", "skip #",
                       "skip ahead", "skip forward", "fast forward", "jump ahead")
        rules += back("skip back #", "go back #", "rewind #", "back up #", "back #", "rewind", "back up", "skip back")
        rules += fixed(.pauseVideo, "pause the video", "pause video", "stop the video", "stop video", "pause")
        rules += fixed(.playVideo, "play the video", "play video", "resume", "unpause", "keep going", "play")
        // Steps and slides.
        rules += step("go to step #", "jump to step #", "skip to step #", "show step #", "step #")
        rules += fixed(.ingredients, "go to the ingredients", "go to ingredients", "show ingredients", "ingredients", "start over", "from the top")
        rules += fixed(.whatDoINeed, "what do i need", "what do we need", "what is needed", "what i need", "what ingredients", "which ingredients", "read the ingredients")
        rules += fixed(.timeLeft, "how long left", "how much time", "how much longer", "time left", "how long", "timer status", "check the timer")
        return rules
    }()

    /// Every spoken form with an example number, for the recognizer's vocabulary hints.
    static var allPhrases: [String] {
        rules.map { $0.pattern.map { $0 == "#" ? "ten seconds" : $0 }.joined(separator: " ") }
    }

    struct Match: Equatable {
        let command: VoiceCommand
        /// Index just past the matched phrase, so the caller can mark those words as consumed.
        let end: Int
    }

    /// The first command spoken in `words`. Earliest wins; on a tie the longer phrase wins.
    static func match(_ words: [String]) -> Match? {
        guard !words.isEmpty else { return nil }
        var best: (position: Int, length: Int, command: VoiceCommand)?
        for rule in rules {
            for start in words.indices {
                guard let hit = matches(rule.pattern, at: start, in: words) else { continue }
                if let b = best, b.position < start || (b.position == start && b.length >= hit.length) { break }
                best = (start, hit.length, rule.make(hit.number))
                break
            }
        }
        guard let best else { return nil }
        return Match(command: best.command, end: best.position + best.length)
    }

    static func match(_ transcript: String) -> VoiceCommand? {
        match(tokenize(transcript))?.command
    }

    /// Lowercase words; digits survive so "10" works as well as "ten".
    static func tokenize(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    // MARK: Numbers

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "ninety": 90, "hundred": 100,
        // What recognizers hear for "two" and "four".
        "to": 2, "too": 2, "for": 4,
    ]

    static func numberValue(_ word: String) -> Int? {
        if let digits = Int(word) { return digits }
        return numberWords[word]
    }

    /// Seconds per spoken unit; nil when the word isn't a unit.
    static func unitMultiplier(_ word: String) -> Int? {
        switch word {
        case "second", "seconds", "sec", "secs": 1
        case "minute", "minutes", "min", "mins": 60
        default: nil
        }
    }

    /// Whether `pattern` matches `words` starting at `start`; the length consumed and any number read.
    static func matches(_ pattern: [String], at start: Int, in words: [String]) -> (length: Int, number: Int?)? {
        var i = start
        var number: Int?
        for token in pattern {
            guard i < words.count else { return nil }
            if token == "#" {
                guard let value = numberValue(words[i]) else { return nil }
                i += 1
                // "twenty five": a small number right after a round one adds on.
                var total = value
                if value >= 20, value % 10 == 0, i < words.count, let small = numberValue(words[i]), small < 10, !["a", "an", "to", "too", "for"].contains(words[i]) {
                    total += small
                    i += 1
                }
                if i < words.count, let multiplier = unitMultiplier(words[i]) {
                    total *= multiplier
                    i += 1
                }
                number = total
            } else {
                guard words[i] == token else { return nil }
                i += 1
            }
        }
        return (i - start, number)
    }
}
