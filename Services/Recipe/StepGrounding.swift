import Foundation

/// Keeps the model honest against the transcript it was given.
///
/// Small models sometimes invent a step (or copy one from their instructions) and sometimes stamp
/// a real step with the wrong line's time. Every candidate is checked against the transcript
/// lines of its window: a step nothing in the window mentions is dropped, and a step with a
/// clear match is snapped to the line where those words are actually spoken.
nonisolated enum StepGrounding {
    struct Options: Sendable {
        /// Seconds either side of the reported start to look for the matching line.
        var snapWindow: Double = 45
        /// Content words the step must share with some run of lines to survive.
        var minOverlapToKeep = 2
        /// Overlap needed to move the start to the matching line.
        var minOverlapToSnap = 2
        /// Overlap needed to trust a match found outside `snapWindow`.
        var minOverlapFarAway = 3
        /// How many consecutive lines form one candidate run (auto-captions are ~3 s each).
        var runLength = 3
        init() {}
    }

    struct Match: Equatable {
        var lineIndex: Int
        var overlap: Int
    }

    static func ground(_ steps: [StepCandidate], in lines: [TranscriptLine], options: Options = Options()) -> [StepCandidate] {
        guard !lines.isEmpty else { return steps }
        let runs = contentRuns(of: lines, length: options.runLength)
        let lineWords = lines.map { StepMerger.contentWords($0.text) }

        /// The line inside a matched run where the action is actually spoken: the first line
        /// with a title word, else the first with any step word, else the run's first line.
        func anchor(_ match: Match, titleWords: Set<String>, stepWords: Set<String>) -> Double {
            let range = match.lineIndex..<min(match.lineIndex + options.runLength, lines.count)
            if let i = range.first(where: { !lineWords[$0].isDisjoint(with: titleWords) }) { return lines[i].start }
            if let i = range.first(where: { !lineWords[$0].isDisjoint(with: stepWords) }) { return lines[i].start }
            return lines[match.lineIndex].start
        }

        /// True when the reported start already lies inside a run that mentions the step.
        func alreadyPlaced(_ start: Double, stepWords: Set<String>) -> Bool {
            runs.indices.contains { i in
                guard stepWords.intersection(runs[i]).count >= options.minOverlapToSnap else { return false }
                let first = lines[i].start
                let last = lines[min(i + options.runLength - 1, lines.count - 1)].start
                return start >= first - 1 && start <= last + 6
            }
        }

        return steps.compactMap { step in
            let stepWords = StepMerger.contentWords(step.title + " " + step.instruction)
            let titleWords = StepMerger.contentWords(step.title)
            guard !stepWords.isEmpty else { return nil }
            var out = step
            if let near = bestMatch(stepWords, runs: runs, lines: lines, around: step.startSecond, within: options.snapWindow),
               near.overlap >= options.minOverlapToKeep {
                if !alreadyPlaced(step.startSecond, stepWords: stepWords), near.overlap >= options.minOverlapToSnap {
                    out.startSecond = anchor(near, titleWords: titleWords, stepWords: stepWords)
                }
            } else if let far = bestMatch(stepWords, runs: runs, lines: lines, around: step.startSecond, within: .infinity),
                      far.overlap >= options.minOverlapFarAway {
                out.startSecond = anchor(far, titleWords: titleWords, stepWords: stepWords)
            } else {
                return nil   // nothing in this window says this; the model made it up
            }
            return out
        }
    }

    /// Content words of each line together with the next `length - 1` lines.
    static func contentRuns(of lines: [TranscriptLine], length: Int) -> [Set<String>] {
        lines.indices.map { i in
            let slice = lines[i..<min(i + max(length, 1), lines.count)]
            return StepMerger.contentWords(slice.map(\.text).joined(separator: " "))
        }
    }

    /// The run with the most words in common; ties go to the run closest to `around`.
    static func bestMatch(_ words: Set<String>, runs: [Set<String>], lines: [TranscriptLine],
                          around: Double, within: Double) -> Match? {
        var best: Match?
        for (i, run) in runs.enumerated() {
            let distance = abs(lines[i].start - around)
            guard distance <= within else { continue }
            let overlap = words.intersection(run).count
            guard overlap > 0 else { continue }
            if let b = best {
                let bDistance = abs(lines[b.lineIndex].start - around)
                if overlap > b.overlap || (overlap == b.overlap && distance < bDistance) {
                    best = Match(lineIndex: i, overlap: overlap)
                }
            } else {
                best = Match(lineIndex: i, overlap: overlap)
            }
        }
        return best
    }
}

/// Drops "steps" that are really greetings, sponsor reads, goodbyes or the cook thinking aloud.
nonisolated enum ChatterFilter {
    static let titleWords: Set<String> = [
        "welcome", "intro", "introduction", "introduce", "outro", "subscribe", "sponsor", "sponsored",
        "patreon", "thanks", "thank", "goodbye", "recap", "wait",
    ]
    static let phrases: [String] = [
        "thanks for watching", "thank you for watching", "subscribe", "like and", "hit the bell",
        "in the comments", "sponsor", "patreon", "see you next", "welcome to", "welcome back",
        "i don't know what the time", "what the time is", "if you enjoyed", "link in the description",
        "my cookbook", "check out my",
    ]

    /// Words that carry no cooking content ("So, um, anyway.").
    static let filler: Set<String> = Set([
        "um", "uh", "anyway", "anyways", "okay", "ok", "yeah", "yep", "right", "basically", "actually",
        "literally", "really", "very", "just", "guys", "everyone", "everybody", "hi", "hello", "hey",
        "alright", "cool", "nice", "good", "great", "awesome", "there", "here", "thing", "things", "stuff",
        "bit", "little", "lot", "kind", "sort", "way", "going", "gonna", "let", "lets",
    ].map(StepMerger.stem))

    static func isChatter(title: String, instruction: String) -> Bool {
        let titleWords = StepMerger.contentWords(title)
        if !titleWords.isDisjoint(with: Self.titleWords.map(StepMerger.stem)) { return true }
        let text = (title + " " + instruction).lowercased()
        if phrases.contains(where: text.contains) { return true }
        // Nothing to do: no verb-ish or ingredient-ish content beyond stop words and filler.
        return StepMerger.contentWords(instruction).subtracting(filler).isEmpty
    }
}
