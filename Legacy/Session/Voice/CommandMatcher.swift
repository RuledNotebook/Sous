import Foundation

/// Spoken forms of each command and word-level matching, so "backyard" isn't "back".
nonisolated enum CommandMatcher {
    /// Multi-word forms never start with another command's bare word, because partial
    /// results arrive one word at a time ("start" ... "start timer").
    static func phrases(for command: VoiceCommand) -> [String] {
        switch command {
        case .next:       ["next step", "go forward", "next", "continue", "forward"]
        case .back:       ["previous step", "go back", "previous", "back"]
        case .repeatStep: ["say again", "repeat", "again", "replay"]
        case .pause:      ["pause video", "hold on", "pause"]
        case .play:       ["keep going", "resume", "play"]
        case .startTimer: ["start the timer", "start a timer", "set the timer", "set a timer", "start timer", "set timer"]
        case .stopTimer:  ["stop the timer", "cancel the timer", "dismiss the timer", "stop timer", "cancel timer", "dismiss timer"]
        }
    }

    static var allPhrases: [String] { VoiceCommand.allCases.flatMap(phrases(for:)) }

    struct Match: Equatable {
        let command: VoiceCommand
        /// Index just past the matched phrase, so the caller can mark those words as consumed.
        let end: Int
    }

    /// The first command spoken in `words`. Earliest wins; on a tie the longer phrase wins.
    static func match(_ words: [String]) -> Match? {
        guard !words.isEmpty else { return nil }
        var best: (position: Int, length: Int, command: VoiceCommand)?
        for command in VoiceCommand.allCases {
            for phrase in phrases(for: command) {
                let pattern = tokenize(phrase)
                guard let position = firstIndex(of: pattern, in: words) else { continue }
                if let b = best, b.position < position || (b.position == position && b.length >= pattern.count) { continue }
                best = (position, pattern.count, command)
            }
        }
        guard let best else { return nil }
        return Match(command: best.command, end: best.position + best.length)
    }

    static func match(_ transcript: String) -> VoiceCommand? {
        match(tokenize(transcript))?.command
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    private static func firstIndex(of pattern: [String], in words: [String]) -> Int? {
        guard !pattern.isEmpty, words.count >= pattern.count else { return nil }
        for start in 0...(words.count - pattern.count) where Array(words[start..<(start + pattern.count)]) == pattern {
            return start
        }
        return nil
    }
}
