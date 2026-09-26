import Testing
@testable import CookAlong

struct TranscriptChunkerTests {
    let transcript = SampleTranscripts.shrimpPasta

    @Test func rendersTimestampPrefix() {
        #expect(TranscriptChunker.render(TranscriptLine(start: 42.9, text: "add the garlic")) == "[42s] add the garlic")
        #expect(TranscriptChunker.render(TranscriptLine(start: -3, text: "x")) == "[0s] x")
    }

    @Test func shortTranscriptIsOneWindow() {
        let windows = TranscriptChunker.split(transcript, maxCharacters: 10_000, videoDuration: 190)
        #expect(windows.count == 1)
        #expect(windows[0].lines == transcript)
        #expect(windows[0].startSecond == 0)
        #expect(windows[0].endSecond == 190)
    }

    @Test func windowsRespectBudgetAndCoverEveryLineInOrder() {
        let long = SampleTranscripts.long(minutes: 45)
        let budget = 1_500
        let windows = TranscriptChunker.split(long, maxCharacters: budget, overlapLines: 2, videoDuration: 45 * 60)
        #expect(windows.count > 5)

        // Budget: only a single oversized line may exceed it.
        for w in windows where w.lines.count > 1 { #expect(w.characterCount <= budget) }

        // Coverage: every transcript line appears in at least one window, in order.
        var covered = 0
        var lastStart = -1.0
        for w in windows {
            #expect(w.startSecond > lastStart || w.index == 0)
            lastStart = w.startSecond
            for line in w.lines where line == long[covered] { covered += 1 }
        }
        #expect(covered == long.count)

        // Overlap: consecutive windows share lines, but each has new content.
        for (a, b) in zip(windows, windows.dropFirst()) {
            #expect(!Set(a.lines).intersection(b.lines).isEmpty)
            #expect(b.lines.last != a.lines.last)
            #expect(a.endSecond == b.lines.first(where: { !a.lines.contains($0) })?.start)
        }
        #expect(windows.last?.endSecond == 2700.0)   // Double literal: inside #expect, `45 * 60` is typed Int and never equals a Double?
    }

    @Test func noOverlapWhenAskedForNone() {
        let windows = TranscriptChunker.split(transcript, maxCharacters: 400, overlapLines: 0, videoDuration: 190)
        let all = windows.flatMap(\.lines)
        #expect(all == transcript)
    }

    @Test func oversizedLineBecomesItsOwnWindowAndHalvesByWords() {
        let giant = TranscriptLine(start: 10, text: Array(repeating: "stir", count: 200).joined(separator: " "))
        let lines = [TranscriptLine(start: 0, text: "Hi."), giant, TranscriptLine(start: 20, text: "Done.")]
        let windows = TranscriptChunker.split(lines, maxCharacters: 100, overlapLines: 0, videoDuration: 30)
        #expect(windows.count == 3)
        #expect(windows[1].lines == [giant])

        let halves = TranscriptChunker.halve(windows[1])
        #expect(halves.count == 2)
        #expect(halves.allSatisfy { $0.lines.count == 1 && $0.startSecond == 10 })
        let total = halves.map { $0.lines[0].text.split(separator: " ").count }.reduce(0, +)
        #expect(total == 200)
    }

    @Test func halvingMultiLineWindowSplitsByCharactersAndKeepsBounds() {
        let window = TranscriptWindow(index: 3, lines: transcript, endSecond: 190)
        let halves = TranscriptChunker.halve(window)
        #expect(halves.count == 2)
        #expect(halves[0].lines + halves[1].lines == transcript)
        #expect(halves.allSatisfy { $0.index == 3 })
        #expect(halves[0].endSecond == halves[1].startSecond)
        #expect(halves[1].endSecond == 190)
        let ratio = Double(halves[0].characterCount) / Double(window.characterCount)
        #expect(ratio > 0.3 && ratio < 0.7)
    }

    @Test func singleWordLineCannotBeHalved() {
        let window = TranscriptWindow(index: 0, lines: [TranscriptLine(start: 0, text: "stir")], endSecond: 5)
        #expect(TranscriptChunker.halve(window).count == 1)
    }

    @Test func emptyTranscriptGivesNoWindows() {
        #expect(TranscriptChunker.split([], maxCharacters: 100, videoDuration: 10).isEmpty)
    }
}
