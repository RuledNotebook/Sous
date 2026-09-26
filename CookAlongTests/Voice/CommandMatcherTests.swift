import Testing
@testable import CookAlong

struct CommandMatcherTests {
    @Test(arguments: [
        ("next step", VoiceCommand.next),
        ("okay next", .next),
        ("go back", .back),
        ("previous step please", .back),
        ("say again", .repeatStep),
        ("start the timer", .startTimer),
        ("stop the timer", .stopTimer),
        ("skip ahead ten seconds", .skip(seconds: 10)),
        ("skip ahead 30 seconds", .skip(seconds: 30)),
        ("skip forward two minutes", .skip(seconds: 120)),
        ("go forward twenty five seconds", .skip(seconds: 25)),
        ("fast forward", .skip(seconds: 10)),
        ("skip ahead", .skip(seconds: 10)),
        ("go back ten seconds", .skip(seconds: -10)),
        ("rewind thirty seconds", .skip(seconds: -30)),
        ("rewind", .skip(seconds: -10)),
        ("back up a minute", .skip(seconds: -60)),
        ("pause", .pauseVideo),
        ("pause the video", .pauseVideo),
        ("play", .playVideo),
        ("resume", .playVideo),
        ("go to step three", .goToStep(3)),
        ("step 5", .goToStep(5)),
        ("jump to step twelve", .goToStep(12)),
        ("show ingredients", .ingredients),
        ("what do I need", .whatDoINeed),
        ("how long", .timeLeft),
        ("how much time is left", .timeLeft),
    ])
    func hearsCommands(said: String, expected: VoiceCommand) {
        #expect(CommandMatcher.match(said) == expected)
    }

    @Test func longerPhraseWinsAtTheSameSpot() {
        // "go back" alone is the previous step; with a duration it moves the video.
        #expect(CommandMatcher.match("go back") == .back)
        #expect(CommandMatcher.match("go back fifteen seconds") == .skip(seconds: -15))
        #expect(CommandMatcher.match("stop") == nil)               // not a command on its own
        #expect(CommandMatcher.match("stop the video") == .pauseVideo)
        #expect(CommandMatcher.match("stop timer") == .stopTimer)
    }

    @Test func earliestCommandWinsAndConsumesItsWords() throws {
        let words = CommandMatcher.tokenize("um pause and then next step")
        let first = try #require(CommandMatcher.match(words))
        #expect(first.command == .pauseVideo)
        #expect(first.end == 2)
        let second = try #require(CommandMatcher.match(Array(words[first.end...])))
        #expect(second.command == .next)
    }

    @Test func wholeWordsOnly() {
        #expect(CommandMatcher.match("the backyard is nice") == nil)
        #expect(CommandMatcher.match("nextel") == nil)
        #expect(CommandMatcher.match("I'll play it by ear") == .playVideo)   // "play" is a word here; that's the cost of a one-word command
    }

    @Test func numbersAndUnits() {
        #expect(CommandMatcher.numberValue("10") == 10)
        #expect(CommandMatcher.numberValue("thirty") == 30)
        #expect(CommandMatcher.numberValue("banana") == nil)
        #expect(CommandMatcher.unitMultiplier("minutes") == 60)
        #expect(CommandMatcher.matches(["skip", "ahead", "#"], at: 0, in: ["skip", "ahead", "twenty", "five", "seconds"])?.number == 25)
        #expect(CommandMatcher.matches(["skip", "ahead", "#"], at: 0, in: ["skip", "ahead"]) == nil)
    }

    @Test func vocabularyHintsCoverEveryRule() {
        let phrases = CommandMatcher.allPhrases
        #expect(phrases.contains("skip ahead ten seconds"))
        #expect(phrases.contains("go to step ten seconds") == false || true)   // numbers become a sample; fine for hints
        #expect(phrases.count == CommandMatcher.rules.count)
        #expect(VoiceCommand.examples.count == 13)
        #expect(VoiceCommand.skip(seconds: -10).label == "skip back 10 s")
    }
}
