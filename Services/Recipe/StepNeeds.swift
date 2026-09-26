import Foundation

/// One thing the cook needs for a step: a name, the amount when the step says one, and the
/// Kitchen asset to draw it with.
nonisolated struct StepNeed: Hashable, Sendable {
    var label: String
    var amount: String?
    var asset: String?
}

/// What a step needs, read from its words: "1 cup water", "6 tbsp soy sauce", then anything the
/// scene shows that the amounts didn't cover. Concise on purpose; the sentence stays in read-aloud.
nonisolated enum StepNeeds {
    static let maxNeeds = 6

    private static let units = #"(?:cups?|c\.|tbsps?|tablespoons?|tsps?|teaspoons?|grams?|g|kgs?|kilos?|mls?|litres?|liters?|l|oz|ounces?|lbs?|pounds?|cloves?|pieces?|slices?|sticks?|cans?|tins?|sprigs?|bunch(?:es)?|heads?|stalks?|packets?|packs?|handfuls?|pinch(?:es)?|splash(?:es)?|dash(?:es)?|knobs?|drizzles?|glugs?)"#
    private static let numbers = #"(?:\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?(?:\s*(?:-|–|to)\s*\d+(?:[.,]\d+)?)?|½|¼|¾|⅓|⅔|half an?|a couple of|a few|a pinch of|a handful of|a splash of|a dash of|a knob of|a drizzle of|a little|one|two|three|four|five|six|seven|eight|ten|twelve)"#
    private static let regex = try! NSRegularExpression(
        pattern: #"(?<![\w-])("# + numbers + #")\s*("# + units + #")?\s*(?:of\s+)?((?:[a-z][a-z'’-]*\s?){1,4}?)(?=\s*(?:[,.;:!?)]|\b(?:and|into|to|in|on|onto|with|until|for|then|over|at|per|or|so|while|plus|each)\b|$))"#,
        options: [.caseInsensitive])

    /// Amount + item pairs in the order they appear.
    static func quantities(in text: String) -> [(amount: String, item: String)] {
        let lower = text.replacingOccurrences(of: "\n", with: " ")
        var out: [(String, String)] = []
        for m in regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            func group(_ i: Int) -> String? {
                guard m.range(at: i).location != NSNotFound, let r = Range(m.range(at: i), in: lower) else { return nil }
                return String(lower[r]).trimmingCharacters(in: .whitespaces)
            }
            guard let number = group(1), let rawItem = group(3) else { continue }
            let unit = group(2)
            let item = clean(rawItem)
            guard !item.isEmpty, !stopItems.contains(item.lowercased()) else { continue }
            // "a pinch of", "a splash of" are measures in themselves. A count or a soft amount
            // ("2", "one", "a few", "a little") only counts when it counts a known ingredient.
            let phrase = number.lowercased()
            let isMeasure = phrase.range(of: #"^a (?:pinch|handful|splash|dash|knob|drizzle) of$"#, options: .regularExpression) != nil
            let knownItem = KitchenAssets.asset(for: item) != nil || countable.contains { item.lowercased().hasSuffix($0) }
            guard unit != nil || isMeasure || knownItem else { continue }
            let amount = [number, unit].compactMap { $0 }.joined(separator: " ")
            out.append((normalizeAmount(amount), item))
        }
        return out
    }

    static func needs(for step: RecipeStep) -> [StepNeed] {
        var needs: [StepNeed] = []
        var covered: Set<String> = []
        for (amount, item) in quantities(in: step.instruction) {
            let asset = KitchenAssets.asset(for: item)
            let key = asset ?? item.lowercased()
            guard covered.insert(key).inserted else { continue }
            needs.append(StepNeed(label: item, amount: amount, asset: asset))
        }
        for scene in step.sceneItems where needs.count < maxNeeds {
            let key = scene.asset ?? scene.label.lowercased()
            guard covered.insert(key).inserted else { continue }
            needs.append(StepNeed(label: scene.asset.map(displayName(for:)) ?? scene.label, amount: nil, asset: scene.asset))
        }
        return Array(needs.prefix(maxNeeds))
    }

    /// What to call an asset on screen: "droplet" is water, "cut_of_meat" is meat.
    static func displayName(for asset: String) -> String {
        if let name = displayNames[asset] { return name }
        return asset.replacingOccurrences(of: "_", with: " ")
    }

    private static let displayNames: [String: String] = [
        "droplet": "water", "cut_of_meat": "meat", "poultry_leg": "chicken", "meat_on_bone": "meat",
        "sheaf_of_rice": "rice", "cooked_rice": "rice", "hot_pepper": "chili", "leafy_green": "greens",
        "ginger_root": "ginger", "glass_of_milk": "milk", "honey_pot": "honey", "herb": "herbs",
        "ear_of_corn": "corn", "pot_of_food": "stew", "shallow_pan_of_food": "pan", "steaming_bowl": "noodles",
        "bowl_with_spoon": "bowl", "pouring_liquid": "liquid", "fried_shrimp": "shrimp", "cheese_wedge": "cheese",
        "chocolate_bar": "chocolate", "baguette_bread": "bread", "green_apple": "apple", "red_apple": "apple",
        "kiwi_fruit": "kiwi", "bell_pepper": "pepper", "pea_pod": "peas", "canned_food": "tin", "ice": "ice",
        "fire": "heat", "fork_and_knife": "cutlery", "fork_and_knife_with_plate": "plate", "kitchen_knife": "knife",
        "timer_clock": "timer", "hot_beverage": "tea", "roasted_sweet_potato": "sweet potato",
    ]

    // MARK: Helpers

    private static let stopItems: Set<String> = ["minutes", "minute", "min", "mins", "seconds", "second", "hours", "hour",
                                                  "degrees", "side", "sides", "times", "time", "inch", "inches", "cm", "percent"]
    private static let countable = ["egg", "eggs", "onion", "onions", "lemon", "lemons", "lime", "limes", "breast", "breasts",
                                    "thigh", "thighs", "fillet", "fillets", "clove", "cloves", "chili", "chilli", "chilies",
                                    "chillies", "potato", "potatoes", "carrot", "carrots", "tomato", "tomatoes", "pepper", "peppers"]

    private static func clean(_ item: String) -> String {
        var words = item.split(separator: " ").map(String.init)
        while let last = words.last, ["and", "the", "a", "an", "of", "your", "some", "more"].contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, ["the", "your", "some", "more", "fresh"].contains(first.lowercased()) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    private static func normalizeAmount(_ amount: String) -> String {
        amount.replacingOccurrences(of: "tablespoons", with: "tbsp").replacingOccurrences(of: "tablespoon", with: "tbsp")
            .replacingOccurrences(of: "teaspoons", with: "tsp").replacingOccurrences(of: "teaspoon", with: "tsp")
            .replacingOccurrences(of: "grams", with: "g").replacingOccurrences(of: "gram", with: "g")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
