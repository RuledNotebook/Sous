import Foundation

/// A contiguous slice of the transcript that is small enough for one model call.
nonisolated struct TranscriptWindow: Hashable, Sendable {
    /// Position among the windows produced by `split` (video order). A window halved after a
    /// context overflow keeps its parent's index, so order by `startSecond`, not by `index`.
    var index: Int
    var lines: [TranscriptLine]
    /// Second where the next window's new content starts, or the end of the video for the last one.
    var endSecond: Double

    var startSecond: Double { lines.first?.start ?? 0 }
    var rendered: String { TranscriptChunker.render(lines) }
    var characterCount: Int { rendered.count }
}

/// Splits a transcript into model-sized windows and shrinks windows that still overflow.
nonisolated enum TranscriptChunker {
    /// The line format every prompt refers to: `[42s] now add the garlic`.
    static func render(_ line: TranscriptLine) -> String {
        "[\(Int(max(line.start, 0).rounded(.down)))s] \(line.text)"
    }

    static func render(_ lines: [TranscriptLine]) -> String {
        lines.map(render).joined(separator: "\n")
    }

    /// Greedy split into windows of at most `maxCharacters` rendered characters.
    ///
    /// Consecutive windows share up to `overlapLines` lines (capped at a third of the budget) so a
    /// step spoken across a boundary is seen whole by at least one window; `StepMerger` removes
    /// the duplicate. Every window contains at least one line that no earlier window covered, so
    /// the split always terminates and covers the whole transcript in order. A single line longer
    /// than the budget becomes its own window; the pipeline halves it if the model rejects it.
    static func split(_ lines: [TranscriptLine], maxCharacters: Int, overlapLines: Int = 2,
                      videoDuration: Double) -> [TranscriptWindow] {
        guard !lines.isEmpty else { return [] }
        let budget = max(maxCharacters, 1)
        var windows: [TranscriptWindow] = []
        var nextNew = 0         // first line not yet covered by any window
        var windowStart = 0     // where the current window begins (may include overlap)

        while nextNew < lines.count {
            var end = windowStart
            var chars = 0
            while end < lines.count {
                let length = render(lines[end]).count + (end > windowStart ? 1 : 0)
                let isNew = end >= nextNew
                if isNew, end > nextNew, chars + length > budget { break }
                chars += length
                end += 1
            }

            let slice = Array(lines[windowStart..<end])
            let endSecond = end < lines.count ? lines[end].start : max(videoDuration, slice.last?.start ?? 0)
            windows.append(TranscriptWindow(index: windows.count, lines: slice, endSecond: endSecond))

            let previousStart = windowStart
            nextNew = end
            // Overlap: walk back up to `overlapLines`, but never past the previous window's start
            // and never more than a third of the budget, so the overlap can't crowd out new lines.
            var start = end
            var overlapChars = 0
            while end - start < overlapLines, start - 1 > previousStart {
                let length = render(lines[start - 1]).count + 1
                if overlapChars + length > budget / 3 { break }
                overlapChars += length
                start -= 1
            }
            windowStart = start
        }
        return windows
    }

    /// Splits a window into two roughly equal halves by character count, for retrying after a
    /// context-window overflow. A single-line window is split by words (both halves keep the
    /// line's timestamp). Returns the window unchanged only when it cannot be split any further.
    static func halve(_ window: TranscriptWindow) -> [TranscriptWindow] {
        if window.lines.count >= 2 {
            let total = window.characterCount
            var cut = 0
            var chars = 0
            while cut < window.lines.count - 1, chars + render(window.lines[cut]).count + 1 <= total / 2 {
                chars += render(window.lines[cut]).count + 1
                cut += 1
            }
            cut = max(cut, 1)
            let first = Array(window.lines[..<cut])
            let second = Array(window.lines[cut...])
            return [
                TranscriptWindow(index: window.index, lines: first, endSecond: second[0].start),
                TranscriptWindow(index: window.index, lines: second, endSecond: window.endSecond),
            ]
        }
        guard let line = window.lines.first else { return [window] }
        let words = line.text.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 2 else { return [window] }
        let mid = words.count / 2
        let a = TranscriptLine(start: line.start, text: words[..<mid].joined(separator: " "))
        let b = TranscriptLine(start: line.start, text: words[mid...].joined(separator: " "))
        return [
            TranscriptWindow(index: window.index, lines: [a], endSecond: line.start),
            TranscriptWindow(index: window.index, lines: [b], endSecond: window.endSecond),
        ]
    }

    /// Rough token estimate for routing decisions (English prose runs about 4 characters per token).
    static func estimatedTokens(_ lines: [TranscriptLine]) -> Int {
        render(lines).count / 4
    }
}
