import Foundation

/// Parses the text a user copies from YouTube's "Show transcript" panel into timestamped lines.
///
/// Both layouts are handled:
///
///     0:15                      0:15 Get a big pot of water on
///     Get a big pot of water on 0:22 and salt it well
///     0:22
///     and salt it well
///
/// as well as `[0:15]`, `(0:15)`, `0:15 - text`, `1:02:15` hour stamps, tabs, header lines
/// ("Transcript", "English (auto-generated)") and stage directions like `[Music]`.
nonisolated enum PastedTranscript {
    /// Optional bracket, h:mm:ss or m:ss, optional bracket, optional separator, then the rest.
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^\s*[\[\(]?\s*((?:\d{1,2}:)?\d{1,2}:\d{2})\s*[\]\)]?\s*(?:[-–—:|]\s*)?(.*)$"#)
    private static let stageDirection = try! NSRegularExpression(pattern: #"^\s*[\[\(][^\]\)]*[\]\)]\s*$"#)
    private static let headers: Set<String> = ["transcript", "show transcript", "english", "english (auto-generated)",
                                                "english (united kingdom)", "english (united states)", "auto-generated"]

    static func looksLikeTranscript(_ text: String) -> Bool {
        (try? parse(text))?.isEmpty == false
    }

    /// Timestamped lines in the order pasted. Throws `RecipeSourceError.transcriptUnreadable`
    /// when the text has no timestamps at all.
    static func parse(_ text: String) throws -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        var pending: Double?          // a timestamp on its own line, waiting for its text
        var sawTimestamp = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if isStageDirection(line) { continue }

            if let (seconds, rest) = split(line) {
                sawTimestamp = true
                if rest.isEmpty {
                    pending = seconds
                } else {
                    pending = nil
                    append(&lines, seconds, rest)
                }
                continue
            }

            if let seconds = pending {
                append(&lines, seconds, line)
                pending = nil
            } else if !lines.isEmpty {
                // Wrapped continuation of the previous line.
                let last = lines.removeLast()
                lines.append(TranscriptLine(start: last.start, text: last.text + " " + line))
            } else if headers.contains(line.lowercased()) || !sawTimestamp {
                continue   // panel header, or a stray line before the first timestamp
            }
        }
        guard sawTimestamp, !lines.isEmpty else { throw RecipeSourceError.transcriptUnreadable }
        return lines
    }

    /// Seconds for "1:05", "01:05", "1:02:05"; nil if it isn't a timestamp.
    static func seconds(from stamp: String) -> Double? {
        let parts = stamp.split(separator: ":").map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }), (2...3).contains(parts.count) else { return nil }
        let values = parts.compactMap { $0 }
        return values.reduce(0) { $0 * 60 + Double($1) }
    }

    private static func split(_ line: String) -> (Double, String)? {
        guard let m = lineRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let stampRange = Range(m.range(at: 1), in: line),
              let seconds = seconds(from: String(line[stampRange])) else { return nil }
        let rest = Range(m.range(at: 2), in: line).map { String(line[$0]) } ?? ""
        return (seconds, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isStageDirection(_ line: String) -> Bool {
        stageDirection.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// Lines that share a timestamp are one line.
    private static func append(_ lines: inout [TranscriptLine], _ seconds: Double, _ text: String) {
        let cleaned = text.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        if let last = lines.last, last.start == seconds {
            lines[lines.count - 1] = TranscriptLine(start: seconds, text: last.text + " " + cleaned)
        } else {
            lines.append(TranscriptLine(start: seconds, text: cleaned))
        }
    }

    /// A working video length when we only have the transcript: a little past the last line.
    static func estimatedDuration(of lines: [TranscriptLine]) -> Double {
        (lines.last?.start ?? 0) + 15
    }
}
