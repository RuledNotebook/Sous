import Foundation
import Testing
@testable import CookAlong

struct PastedTranscriptTests {
    /// YouTube's web panel: the timestamp sits on its own line above the text.
    static let stacked = """
        Transcript
        English (auto-generated)
        0:00
        [Music]
        0:05
        hey guys how you doing Dave from cooking
        0:06
        share here today we're doing out one of
        0:08
        my all-time favorite meals chicken
        1:02
        cube up the chicken
        1:02:15
        into the oven for 25 minutes
        """

    /// Mobile / other copies: "0:15 text" on one line, sometimes in brackets or with a dash.
    static let inline = """
        0:15 Get a big pot of water on and salt it well.
        [0:22] Pat the shrimp dry, both sides.
        (0:40) - Now the garlic, thin slices.
        0:48\tA good handful of parsley.
        01:00 – Water's boiling, spaghetti goes in.
        """

    @Test func parsesTheStackedLayout() throws {
        let lines = try PastedTranscript.parse(Self.stacked)
        #expect(lines.map(\.start) == [5, 6, 8, 62, 3735])
        #expect(lines[0].text == "hey guys how you doing Dave from cooking")
        #expect(lines[3].text == "cube up the chicken")
        #expect(lines[4].text == "into the oven for 25 minutes")
    }

    @Test func parsesTheInlineLayout() throws {
        let lines = try PastedTranscript.parse(Self.inline)
        #expect(lines.map(\.start) == [15, 22, 40, 48, 60])
        #expect(lines.map(\.text) == [
            "Get a big pot of water on and salt it well.",
            "Pat the shrimp dry, both sides.",
            "Now the garlic, thin slices.",
            "A good handful of parsley.",
            "Water's boiling, spaghetti goes in.",
        ])
    }

    @Test func dropsHeadersAndStageDirectionsAndBlankLines() throws {
        let text = "Show transcript\n\n0:00\n[Music]\n\n0:03\n[Applause]\n0:04\nwelcome back\n\n"
        let lines = try PastedTranscript.parse(text)
        #expect(lines == [TranscriptLine(start: 4, text: "welcome back")])
    }

    @Test func joinsWrappedContinuationLines() throws {
        let text = "0:10\nfirst we dice the onion nice\nand small\n0:20\nthen the garlic"
        let lines = try PastedTranscript.parse(text)
        #expect(lines.map(\.text) == ["first we dice the onion nice and small", "then the garlic"])
        #expect(lines.map(\.start) == [10, 20])
    }

    @Test func mergesLinesThatShareATimestamp() throws {
        let lines = try PastedTranscript.parse("0:10 one\n0:10 two\n0:11 three")
        #expect(lines.map(\.text) == ["one two", "three"])
    }

    @Test func rejectsTextWithoutTimestamps() {
        #expect(throws: RecipeSourceError.transcriptUnreadable) {
            try PastedTranscript.parse("Just some notes I typed about the recipe.\nNo times anywhere.")
        }
        #expect(throws: RecipeSourceError.transcriptUnreadable) { try PastedTranscript.parse("") }
        #expect(RecipeSourceError.transcriptUnreadable.errorDescription?.contains("Show transcript") == true)
    }

    @Test func parsesTimestamps() {
        #expect(PastedTranscript.seconds(from: "0:05") == 5)
        #expect(PastedTranscript.seconds(from: "12:34") == 754)
        #expect(PastedTranscript.seconds(from: "1:02:03") == 3723)
        #expect(PastedTranscript.seconds(from: "5") == nil)
        #expect(PastedTranscript.seconds(from: "a:b") == nil)
    }

    @Test func estimatesDurationJustPastTheLastLine() throws {
        let lines = try PastedTranscript.parse(Self.inline)
        #expect(PastedTranscript.estimatedDuration(of: lines) == 75)
        #expect(PastedTranscript.looksLikeTranscript(Self.inline))
        #expect(!PastedTranscript.looksLikeTranscript("hello"))
    }
}
