import Foundation
import os

// Ingredients are only as real as the words behind them. Every extractor is asked for the exact
// transcript words that name each ingredient; the code below checks those words are really in
// the transcript, drops what isn't, and keeps a step's picture items to what the step or its
// stretch of transcript mentions.

/// What the transcript-reading model was and how much of the transcript it saw.
nonisolated struct ModelReport: Sendable, Equatable {
    var model: String
    var transcriptLines: Int
    var transcriptCharacters: Int
    var sentCharacters: Int

    var isThinned: Bool { sentCharacters < transcriptCharacters }

    var description: String {
        let share = transcriptCharacters == 0 ? 100 : Int((Double(sentCharacters) / Double(transcriptCharacters) * 100).rounded())
        return "model: \(model) | transcript: \(transcriptLines) lines, \(transcriptCharacters) chars | sent: \(sentCharacters) chars (\(share)%)"
            + (isThinned ? " THINNED" : "")
    }
}

nonisolated enum IngredientGrounding {
    /// The rule every extractor gets, word for word.
    static let promptRule = """
        Only list ingredients the cook actually says. For each ingredient give its name, the amount \
        if one is said (else an empty string), evidence (the exact words from the transcript that \
        name it, copied word-for-word, punctuation and all) and second (the timestamp of the \
        transcript line those words are on). Do not add ingredients that are typical for this \
        dish but not said.
        """

    /// Lowercase, punctuation stripped, single spaces: what both sides of every comparison become.
    static func normalize(_ text: String) -> String {
        let mapped = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Checks each claim's evidence against the transcript. Duplicate names collapse onto the
    /// first claim; a found ingredient's `second` snaps to the line its words are on.
    static func verify(_ claims: [IngredientEvidence], transcript: [TranscriptLine]) -> [IngredientEvidence] {
        let haystack = " " + normalize(transcript.map(\.text).joined(separator: " ")) + " "
        var seen: Set<String> = []
        var out: [IngredientEvidence] = []
        for claim in claims {
            let key = normalize(claim.name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let needle = normalize(claim.evidence)
            var row = claim
            row.found = !needle.isEmpty && haystack.contains(" " + needle + " ")
            if row.found == true, let second = lineStart(containing: needle, in: transcript) { row.second = second }
            out.append(row)
        }
        return out
    }

    /// The ingredient lines the recipe should show: only verified ones, with amounts.
    static func kept(_ rows: [IngredientEvidence]) -> [String] {
        rows.filter { $0.found == true }.map(\.label)
    }

    /// "ingredient | evidence | found" for the console.
    static func table(_ rows: [IngredientEvidence]) -> String {
        let header = [("ingredient", "evidence", "found")]
        let body = rows.map { ($0.label, "\"\($0.evidence.prefix(60))\"", $0.found.map { $0 ? "yes" : "no" } ?? "n/a") }
        let all = header + body
        let w1 = all.map { $0.0.count }.max() ?? 10
        let w2 = all.map { $0.1.count }.max() ?? 10
        func pad(_ s: String, _ w: Int) -> String { s + String(repeating: " ", count: max(0, w - s.count)) }
        var lines = all.map { "\(pad($0.0, w1)) | \(pad($0.1, w2)) | \($0.2)" }
        lines.insert(String(repeating: "-", count: w1 + 1) + "+" + String(repeating: "-", count: w2 + 2) + "+------", at: 1)
        let found = rows.filter { $0.found == true }.count
        lines.append("\(found) of \(rows.count) ingredients found in the transcript")
        return lines.joined(separator: "\n")
    }

    /// Start of the first line (joined with the next, for words that straddle a break) holding `needle`.
    static func lineStart(containing needle: String, in transcript: [TranscriptLine]) -> Int? {
        for i in transcript.indices {
            let text = i + 1 < transcript.count ? transcript[i].text + " " + transcript[i + 1].text : transcript[i].text
            if (" " + normalize(text) + " ").contains(" " + needle + " ") { return Int(transcript[i].start) }
        }
        return nil
    }
}

/// A step's picture items only show what the step says or what the cook says during it.
nonisolated enum StepItemGrounding {
    static func apply(to steps: [RecipeStep], transcript: [TranscriptLine]) -> [RecipeStep] {
        steps.enumerated().map { index, step in
            let end = index + 1 < steps.count ? steps[index + 1].startSecond : Int.max
            let section = transcript
                .filter { Int($0.start) >= step.startSecond && Int($0.start) < end }
                .map(\.text).joined(separator: " ")
            let stepText = step.title + ". " + step.instruction
            let inStep = KitchenAssets.items(in: stepText, limit: 6)
            let mentioned = Set(inStep + KitchenAssets.items(in: section, limit: 40))
            var out = step
            // The model's picks survive when the step or its stretch of transcript mentions them;
            // otherwise the step's own sentence decides, and only then the transcript (sparingly).
            var kept: [String] = []
            for asset in (step.items ?? []).compactMap(KitchenAssets.canonical) where mentioned.contains(asset) && !kept.contains(asset) {
                kept.append(asset)
            }
            if !kept.isEmpty {
                out.items = kept
            } else if !inStep.isEmpty {
                out.items = inStep
            } else {
                out.items = Array(KitchenAssets.items(in: section, limit: 3))
            }
            return out
        }
    }
}

/// What a recipe looks like when it comes back from a cloud model as JSON. Ingredients may be
/// objects with evidence (the current schemas) or plain strings (older ones, kept decodable).
nonisolated struct GroundedRecipePayload: Decodable {
    struct Step: Decodable {
        let title: String
        let instruction: String
        let startSecond: Double
        let minutes: Int
        let isHandsOn: Bool
        let needsTimer: Bool
        let tip: String?
        let imagePrompt: String?
        let vessel: String?
        let items: [String]?
    }

    struct Ingredient: Decodable {
        let name: String
        let amount: String
        let evidence: String
        let second: Double

        private enum CodingKeys: String, CodingKey { case name, amount, evidence, second }

        init(name: String, amount: String, evidence: String, second: Double) {
            self.name = name; self.amount = amount; self.evidence = evidence; self.second = second
        }

        init(from decoder: any Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
                self.init(name: text, amount: "", evidence: "", second: 0)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(name: try c.decode(String.self, forKey: .name),
                      amount: (try? c.decode(String.self, forKey: .amount)) ?? "",
                      evidence: (try? c.decode(String.self, forKey: .evidence)) ?? "",
                      second: (try? c.decode(Double.self, forKey: .second)) ?? 0)
        }

        var claim: IngredientEvidence {
            IngredientEvidence(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                               amount: amount.trimmingCharacters(in: .whitespacesAndNewlines),
                               evidence: evidence.trimmingCharacters(in: .whitespacesAndNewlines),
                               second: Int(second.rounded()), found: nil)
        }
    }

    let title: String
    let servings: Int
    let difficulty: String
    let ingredients: [Ingredient]
    let durationSeconds: Double?
    let steps: [Step]

    /// The shared sanity pass, with the ingredient claims attached (unverified until grounded).
    @MainActor
    func recipe(videoDuration: Double? = nil) -> Recipe {
        let candidates = steps.enumerated().map { order, s in
            StepCandidate(title: s.title, instruction: s.instruction, startSecond: s.startSecond,
                          minutes: s.minutes, isHandsOn: s.isHandsOn, needsTimer: s.needsTimer,
                          tip: s.tip ?? "", imagePrompt: s.imagePrompt ?? "", vessel: s.vessel ?? "", items: s.items ?? [], order: order)
        }
        let ordered = candidates.sorted { ($0.startSecond, $0.order) < ($1.startSecond, $1.order) }
        let finished = ChunkedRecipePipeline.finalize(ordered, videoDuration: videoDuration ?? durationSeconds ?? 0)
        let claims = ingredients.map(\.claim)
        return Recipe(title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Recipe from video",
                      servings: (1...12).contains(servings) ? servings : 4,
                      difficulty: ["easy", "medium", "hard"].contains(difficulty) ? difficulty : ChunkedRecipePipeline.difficulty(for: finished),
                      ingredients: ChunkedRecipePipeline.dedupeIngredients(claims.map(\.label)),
                      steps: finished,
                      ingredientEvidence: claims)
    }
}

/// Grounds a finished recipe against the transcript it came from.
nonisolated enum RecipeGrounding {
    static let log = Logger(subsystem: "com.cookalong.CookAlong", category: "grounding")

    /// Verifies the ingredient claims (keeping only found ones), keeps step items to what is said,
    /// and returns the console table.
    @MainActor
    static func ground(_ recipe: Recipe, transcript: [TranscriptLine]) -> (recipe: Recipe, table: String) {
        var out = recipe
        var table = "(no ingredient evidence to check)"
        if let claims = recipe.ingredientEvidence, !claims.isEmpty {
            let rows = IngredientGrounding.verify(claims, transcript: transcript)
            out.ingredientEvidence = rows
            out.ingredients = ChunkedRecipePipeline.dedupeIngredients(IngredientGrounding.kept(rows))
            table = IngredientGrounding.table(rows)
        }
        out.steps = StepItemGrounding.apply(to: recipe.steps, transcript: transcript)
        return (out, table)
    }
}
