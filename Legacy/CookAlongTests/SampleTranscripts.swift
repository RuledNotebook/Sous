@testable import CookAlong

/// Fake transcripts for the tests. No model calls anywhere in this target.
enum SampleTranscripts {
    /// ~4 minute garlic butter shrimp pasta. Includes the two failure modes the prompt targets:
    /// an action mentioned before it starts, and a jump-cut over a wait.
    static let shrimpPasta: [TranscriptLine] = [
        .init(start: 0,   text: "Hey everyone, today we're making garlic butter shrimp pasta."),
        .init(start: 5,   text: "You'll need 200 grams of spaghetti, 250 grams of shrimp, four cloves of garlic, three tablespoons of butter, a lemon, chili flakes and parsley."),
        .init(start: 14,  text: "First thing, get a big pot of water on and salt it well, it should taste like the sea."),
        .init(start: 22,  text: "While that comes up to the boil we'll do the garlic, but let me pat the shrimp dry first."),
        .init(start: 30,  text: "Paper towel, both sides. Dry shrimp brown, wet shrimp steam."),
        .init(start: 40,  text: "Okay now the garlic. Thin slices, they turn golden evenly."),
        .init(start: 48,  text: "And a good handful of parsley, roughly chopped."),
        .init(start: 60,  text: "Water's boiling. Spaghetti goes in, cook it one minute less than the packet says, about nine minutes."),
        .init(start: 70,  text: "Save a mug of the pasta water before you drain it, we need it later."),
        .init(start: 78,  text: "Pan on medium high, one tablespoon of butter."),
        .init(start: 85,  text: "Shrimp in, one minute per side, don't crowd the pan."),
        .init(start: 96,  text: "Look at that colour. Out they come, set them aside."),
        .init(start: 105, text: "Heat down to medium, rest of the butter, the garlic and a pinch of chili."),
        .init(start: 114, text: "Cook until fragrant and pale gold, pull it before the garlic browns."),
        .init(start: 130, text: "Pasta's done. Straight into the pan with a splash of that pasta water."),
        .init(start: 140, text: "Juice of half a lemon. Toss until glossy."),
        .init(start: 150, text: "Shrimp back in, parsley, a bit of lemon zest."),
        .init(start: 160, text: "Give it a final toss and taste for salt."),
        .init(start: 175, text: "Plate it up and serve right away."),
        .init(start: 185, text: "That's it. Thanks for watching, see you next time."),
    ]

    /// A baked dish with a jump-cut: "25 minutes" in the oven takes 3 seconds of video.
    static let bakedSalmon: [TranscriptLine] = [
        .init(start: 0,   text: "Quick baked salmon tonight."),
        .init(start: 6,   text: "Oven on to 200 degrees, let it preheat."),
        .init(start: 12,  text: "Salmon on a tray, olive oil, salt, pepper and lemon slices on top."),
        .init(start: 40,  text: "Into the oven for 25 minutes."),
        .init(start: 43,  text: "And here it is out of the oven, look at that colour."),
        .init(start: 52,  text: "Let it rest for five minutes before you dig in."),
        .init(start: 60,  text: "Serve with the roasted lemon."),
    ]

    /// Repeats a block of lines with rising timestamps to simulate a long video.
    static func long(minutes: Int) -> [TranscriptLine] {
        let block = shrimpPasta.dropFirst().dropLast()   // drop intro/outro so the repeats look like ongoing cooking
        let blockLength = 200.0
        var lines: [TranscriptLine] = []
        var offset = 0.0
        while offset + blockLength <= Double(minutes * 60) {
            for line in block {
                lines.append(TranscriptLine(start: line.start + offset, text: line.text))
            }
            offset += blockLength
        }
        return lines
    }
}
