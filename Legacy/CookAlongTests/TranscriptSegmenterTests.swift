import Testing
@testable import CookAlong

struct TranscriptSegmenterTests {
    private func words(_ spec: [(Double, String)]) -> [TranscriptWord] {
        spec.map { TranscriptWord(time: $0.0, duration: 0.3, text: $0.1) }
    }

    @Test func breaksAtSentenceEndOnceLongEnough() {
        let w = words([(0, "Salt"), (0.5, "the"), (1.0, "water"), (1.5, "well."), (2.0, "It"), (2.5, "should"),
                       (3.0, "taste"), (3.5, "like"), (4.0, "the"), (4.5, "sea."), (5.0, "Now"), (5.5, "garlic.")])
        let lines = TranscriptSegmenter().lines(from: w)
        // "well." at 1.5 s is too short a line to break on (min 2.5 s, < 6 words), "sea." closes the line.
        #expect(lines.map(\.start) == [0, 5.0])
        #expect(lines[0].text == "Salt the water well. It should taste like the sea.")
        #expect(lines[1].text == "Now garlic.")
    }

    @Test func breaksOnSilence() {
        let w = words([(10, "Pan"), (10.4, "on."), (14, "Shrimp"), (14.4, "in.")])
        let lines = TranscriptSegmenter().lines(from: w)
        #expect(lines.count == 2)
        #expect(lines[1].start == 14)
    }

    @Test func hardCapsBySecondsAndWords() {
        var seg = TranscriptSegmenter()
        seg.maxSeconds = 8
        seg.maxWords = 22
        let run = (0..<60).map { (Double($0) * 0.5, "word") }   // no punctuation, no gaps: 30 s of speech
        let lines = seg.lines(from: words(run))
        #expect(lines.count >= 4)
        for line in lines {
            #expect(line.text.split(separator: " ").count <= 22)
        }
        // Every line starts within 8 s of the previous one.
        for (a, b) in zip(lines, lines.dropFirst()) { #expect(b.start - a.start <= 8.5) }
    }

    @Test func dropsEmptyWordsAndKeepsOrder() {
        let w = words([(1.0, ""), (1.5, "Boil"), (2.0, "  "), (2.5, "water.")])
        let lines = TranscriptSegmenter().lines(from: w)
        #expect(lines.count == 1)
        #expect(lines[0].start == 1.5)
        #expect(lines[0].text == "Boil water.")
    }
}
