import Foundation

/// The bundled ingredient and tool art: Microsoft Fluent Emoji, 3D style (MIT), in Assets.xcassets/Kitchen.
/// `asset(for:)` turns ingredient or step text into an asset name; `items(in:)` finds every ingredient a step mentions.
nonisolated enum KitchenAssets {
    /// Every imageset name in the Kitchen folder.
    static let all: [String] = ["avocado", "bacon", "bagel", "baguette_bread", "banana", "beans", "beer_mug", "bell_pepper", "blueberries", "bowl_with_spoon", "bread", "broccoli", "burrito", "butter", "canned_food", "carrot", "cheese_wedge", "cherries", "chestnut", "chocolate_bar", "chopsticks", "coconut", "cooked_rice", "cookie", "cooking", "crab", "croissant", "cucumber", "curry_rice", "cut_of_meat", "droplet", "dumpling", "ear_of_corn", "egg", "eggplant", "falafel", "fire", "fish", "flatbread", "fondue", "fork_and_knife", "fork_and_knife_with_plate", "fried_shrimp", "garlic", "ginger_root", "glass_of_milk", "grapes", "green_apple", "green_salad", "hamburger", "herb", "honey_pot", "hot_beverage", "hot_dog", "hot_pepper", "ice", "jar", "kitchen_knife", "kiwi_fruit", "leafy_green", "lemon", "lime", "lobster", "mango", "meat_on_bone", "mushroom", "olive", "onion", "oyster", "pancakes", "pea_pod", "peach", "peanuts", "pear", "pie", "pineapple", "pizza", "popcorn", "pot_of_food", "potato", "poultry_leg", "pouring_liquid", "pretzel", "red_apple", "rice_ball", "rice_cracker", "roasted_sweet_potato", "sake", "salt", "sandwich", "seedling", "shallow_pan_of_food", "sheaf_of_rice", "shrimp", "spaghetti", "spoon", "squid", "steaming_bowl", "strawberry", "sunflower", "sushi", "taco", "tamale", "tangerine", "teapot", "timer_clock", "tomato", "waffle", "watermelon", "wine_glass"]
    static let allSet = Set(all)

    /// Assets that stand for a vessel or tool rather than food; never shown as a step's item.
    static let vesselAssets: Set<String> = ["pot_of_food", "shallow_pan_of_food", "cooking", "bowl_with_spoon",
                                            "fork_and_knife", "fork_and_knife_with_plate", "kitchen_knife", "fire",
                                            "timer_clock", "spoon", "chopsticks", "steaming_bowl"]

    /// Short names for the extraction prompt: common ingredients only, so the on-device context stays small.
    static let promptList: [String] = ["garlic", "onion", "carrot", "tomato", "potato", "roasted_sweet_potato", "lemon", "lime",
        "hot_pepper", "bell_pepper", "ginger_root", "broccoli", "leafy_green", "cucumber", "mushroom", "avocado", "ear_of_corn",
        "eggplant", "beans", "pea_pod", "olive", "herb", "cut_of_meat", "meat_on_bone", "poultry_leg", "bacon", "fish", "shrimp",
        "crab", "squid", "oyster", "cheese_wedge", "glass_of_milk", "butter", "egg", "salt", "jar", "droplet", "honey_pot",
        "cooked_rice", "spaghetti", "bread", "flatbread", "chestnut", "peanuts", "coconut", "chocolate_bar", "wine_glass",
        "red_apple", "banana", "strawberry", "peach", "grapes", "pineapple", "mango", "tangerine", "blueberries", "cherries"]

    /// Words and phrases (lowercase) -> asset. Longer phrases win over shorter ones ("bell pepper" beats "pepper").
    static let aliases: [String: String] = [
        // aromatics
        "garlic": "garlic", "garlic clove": "garlic", "garlic cloves": "garlic", "minced garlic": "garlic", "clove": "garlic", "cloves": "garlic",
        "onion": "onion", "onions": "onion", "scallion": "onion", "scallions": "onion", "spring onion": "onion", "spring onions": "onion",
        "green onion": "onion", "green onions": "onion", "shallot": "onion", "shallots": "onion", "leek": "onion", "leeks": "onion", "red onion": "onion",
        "ginger": "ginger_root", "ginger root": "ginger_root",
        "chili": "hot_pepper", "chilli": "hot_pepper", "chilies": "hot_pepper", "chillies": "hot_pepper", "chili flakes": "hot_pepper",
        "chilli flakes": "hot_pepper", "red pepper flakes": "hot_pepper", "jalapeno": "hot_pepper", "jalapeño": "hot_pepper",
        "cayenne": "hot_pepper", "paprika": "hot_pepper", "chipotle": "hot_pepper", "sriracha": "hot_pepper", "hot sauce": "hot_pepper",
        "bell pepper": "bell_pepper", "bell peppers": "bell_pepper", "capsicum": "bell_pepper", "red pepper": "bell_pepper",
        "green pepper": "bell_pepper", "yellow pepper": "bell_pepper", "peppers": "bell_pepper",
        // vegetables
        "carrot": "carrot", "carrots": "carrot", "tomato": "tomato", "tomatoes": "tomato", "cherry tomatoes": "tomato",
        "tomato paste": "tomato", "tomato sauce": "tomato", "passata": "tomato", "potato": "potato", "potatoes": "potato",
        "sweet potato": "roasted_sweet_potato", "sweet potatoes": "roasted_sweet_potato", "yam": "roasted_sweet_potato",
        "broccoli": "broccoli", "cauliflower": "broccoli", "spinach": "leafy_green", "kale": "leafy_green", "lettuce": "leafy_green",
        "cabbage": "leafy_green", "bok choy": "leafy_green", "arugula": "leafy_green", "rocket": "leafy_green", "chard": "leafy_green",
        "greens": "leafy_green", "salad": "green_salad", "cucumber": "cucumber", "cucumbers": "cucumber", "zucchini": "cucumber",
        "courgette": "cucumber", "mushroom": "mushroom", "mushrooms": "mushroom", "shiitake": "mushroom", "portobello": "mushroom",
        "avocado": "avocado", "avocados": "avocado", "corn": "ear_of_corn", "sweetcorn": "ear_of_corn", "eggplant": "eggplant",
        "aubergine": "eggplant", "peas": "pea_pod", "green beans": "pea_pod", "edamame": "pea_pod", "snap peas": "pea_pod",
        "beans": "beans", "chickpeas": "beans", "lentils": "beans", "black beans": "beans", "kidney beans": "beans",
        "olive": "olive", "olives": "olive", "olive oil": "olive", "oil": "olive", "vegetable oil": "olive", "sesame oil": "olive",
        "herb": "herb", "herbs": "herb", "parsley": "herb", "basil": "herb", "cilantro": "herb", "coriander": "herb", "thyme": "herb",
        "rosemary": "herb", "oregano": "herb", "dill": "herb", "mint": "herb", "chives": "herb", "sage": "herb", "bay leaf": "herb",
        "bay leaves": "herb", "tarragon": "herb", "lemongrass": "herb",
        "lemon": "lemon", "lemons": "lemon", "lemon juice": "lemon", "lemon zest": "lemon", "lime": "lime", "limes": "lime", "lime juice": "lime",
        // protein
        "chicken": "poultry_leg", "chicken breast": "poultry_leg", "chicken thigh": "poultry_leg", "chicken thighs": "poultry_leg",
        "turkey": "poultry_leg", "drumstick": "poultry_leg", "drumsticks": "poultry_leg", "duck": "poultry_leg",
        "beef": "cut_of_meat", "steak": "cut_of_meat", "pork": "cut_of_meat", "lamb": "cut_of_meat", "ground beef": "cut_of_meat",
        "mince": "cut_of_meat", "minced meat": "cut_of_meat", "sausage": "cut_of_meat", "sausages": "cut_of_meat", "meat": "cut_of_meat",
        "veal": "cut_of_meat", "ribs": "meat_on_bone", "pork chop": "meat_on_bone", "chops": "meat_on_bone", "brisket": "meat_on_bone",
        "bacon": "bacon", "pancetta": "bacon", "prosciutto": "bacon", "ham": "bacon", "guanciale": "bacon",
        "fish": "fish", "salmon": "fish", "tuna": "fish", "cod": "fish", "tilapia": "fish", "anchovy": "fish", "anchovies": "fish",
        "sardines": "fish", "fillet": "fish", "fillets": "fish", "trout": "fish", "sea bass": "fish", "halibut": "fish",
        "shrimp": "shrimp", "shrimps": "shrimp", "prawn": "shrimp", "prawns": "shrimp", "fried shrimp": "fried_shrimp",
        "crab": "crab", "lobster": "lobster", "squid": "squid", "calamari": "squid", "octopus": "squid",
        "oyster": "oyster", "oysters": "oyster", "clams": "oyster", "mussels": "oyster", "scallops": "oyster",
        "egg": "egg", "eggs": "egg", "yolk": "egg", "yolks": "egg", "egg white": "egg", "egg whites": "egg",
        "tofu": "cheese_wedge",
        // dairy
        "cheese": "cheese_wedge", "parmesan": "cheese_wedge", "cheddar": "cheese_wedge", "mozzarella": "cheese_wedge", "feta": "cheese_wedge",
        "pecorino": "cheese_wedge", "gouda": "cheese_wedge", "cream cheese": "cheese_wedge", "ricotta": "cheese_wedge", "gruyere": "cheese_wedge",
        "milk": "glass_of_milk", "cream": "glass_of_milk", "heavy cream": "glass_of_milk", "double cream": "glass_of_milk",
        "yogurt": "glass_of_milk", "yoghurt": "glass_of_milk", "buttermilk": "glass_of_milk", "sour cream": "glass_of_milk",
        "butter": "butter", "ghee": "butter", "margarine": "butter",
        // pantry
        "salt": "salt", "sea salt": "salt", "kosher salt": "salt", "black pepper": "salt", "pepper": "salt", "peppercorns": "salt",
        "salt and pepper": "salt", "salted": "salt", "seasoning": "salt",
        "sugar": "jar", "brown sugar": "jar", "flour": "jar", "cornstarch": "jar", "cornflour": "jar", "baking powder": "jar",
        "baking soda": "jar", "yeast": "jar", "spice": "jar", "spices": "jar", "cumin": "jar", "turmeric": "jar", "cinnamon": "jar",
        "nutmeg": "jar", "curry powder": "jar", "garam masala": "jar", "vinegar": "jar", "soy sauce": "jar", "fish sauce": "jar",
        "oyster sauce": "jar", "worcestershire": "jar", "ketchup": "jar", "mustard": "jar", "mayonnaise": "jar", "mayo": "jar",
        "miso": "jar", "tahini": "jar", "vanilla": "jar", "sauce": "jar",
        "water": "droplet", "stock": "droplet", "broth": "droplet", "pasta water": "droplet", "ice": "ice", "ice cubes": "ice",
        "honey": "honey_pot", "maple syrup": "honey_pot", "syrup": "honey_pot",
        "wine": "wine_glass", "red wine": "wine_glass", "white wine": "wine_glass", "beer": "beer_mug", "sake": "sake",
        "coffee": "hot_beverage", "tea": "hot_beverage", "espresso": "hot_beverage",
        "chocolate": "chocolate_bar", "cocoa": "chocolate_bar", "dark chocolate": "chocolate_bar",
        "coconut": "coconut", "coconut milk": "coconut", "coconut cream": "coconut",
        "peanut": "peanuts", "peanuts": "peanuts", "peanut butter": "peanuts", "nuts": "peanuts", "almonds": "peanuts",
        "cashews": "peanuts", "walnuts": "peanuts", "pine nuts": "peanuts", "pecans": "peanuts", "pistachios": "peanuts",
        "chestnut": "chestnut", "chestnuts": "chestnut", "sesame": "sheaf_of_rice", "sesame seeds": "sheaf_of_rice",
        "sprouts": "seedling", "bean sprouts": "seedling", "sunflower seeds": "sunflower",
        // grains and bread
        "rice": "cooked_rice", "basmati": "cooked_rice", "jasmine rice": "cooked_rice", "risotto": "cooked_rice", "arborio": "cooked_rice",
        "spaghetti": "spaghetti", "pasta": "spaghetti", "noodles": "spaghetti", "linguine": "spaghetti", "fettuccine": "spaghetti",
        "penne": "spaghetti", "macaroni": "spaghetti", "tagliatelle": "spaghetti", "rigatoni": "spaghetti", "orzo": "spaghetti",
        "ramen": "steaming_bowl", "udon": "steaming_bowl", "soba": "steaming_bowl",
        "bread": "bread", "toast": "bread", "bun": "bread", "buns": "bread", "breadcrumbs": "bread", "bread crumbs": "bread",
        "panko": "bread", "baguette": "baguette_bread", "tortilla": "flatbread", "tortillas": "flatbread", "pita": "flatbread",
        "naan": "flatbread", "flatbread": "flatbread", "croissant": "croissant", "bagel": "bagel", "pretzel": "pretzel",
        "oats": "sheaf_of_rice", "quinoa": "sheaf_of_rice", "couscous": "cooked_rice", "polenta": "cooked_rice",
        // fruit
        "apple": "red_apple", "apples": "red_apple", "green apple": "green_apple", "banana": "banana", "bananas": "banana",
        "strawberry": "strawberry", "strawberries": "strawberry", "berries": "strawberry", "raspberries": "strawberry",
        "peach": "peach", "peaches": "peach", "apricot": "peach", "grapes": "grapes", "raisins": "grapes", "pineapple": "pineapple",
        "mango": "mango", "orange": "tangerine", "oranges": "tangerine", "tangerine": "tangerine", "clementine": "tangerine",
        "mandarin": "tangerine", "orange juice": "tangerine", "orange zest": "tangerine", "blueberries": "blueberries",
        "cherries": "cherries", "cherry": "cherries", "pear": "pear", "pears": "pear", "kiwi": "kiwi_fruit", "watermelon": "watermelon",
        "melon": "watermelon",
        // dishes and extras
        "curry": "curry_rice", "sushi": "sushi", "dumpling": "dumpling", "dumplings": "dumpling", "gyoza": "dumpling",
        "wonton": "dumpling", "wontons": "dumpling", "ravioli": "dumpling", "pizza": "pizza", "taco": "taco", "tacos": "taco",
        "burrito": "burrito", "sandwich": "sandwich", "burger": "hamburger", "hamburger": "hamburger", "hot dog": "hot_dog",
        "falafel": "falafel", "pancake": "pancakes", "pancakes": "pancakes", "waffle": "waffle", "waffles": "waffle", "pie": "pie",
        "cookie": "cookie", "cookies": "cookie", "popcorn": "popcorn", "fondue": "fondue", "tamale": "tamale", "tamales": "tamale",
        "rice ball": "rice_ball", "onigiri": "rice_ball", "cracker": "rice_cracker", "crackers": "rice_cracker",
        "canned": "canned_food", "can of": "canned_food", "tin of": "canned_food",
        // tools
        "knife": "kitchen_knife", "timer": "timer_clock", "spoon": "spoon", "chopsticks": "chopsticks",
    ]

    /// Phrases to try, longest first, each as normalized words.
    private static let phrases: [(words: [String], asset: String)] = {
        var list: [(words: [String], asset: String)] = aliases.map { (normalize($0.key), $0.value) }
        list += all.map { (normalize($0.replacingOccurrences(of: "_", with: " ")), $0) }
        return list.filter { !$0.words.isEmpty }.sorted { $0.words.count > $1.words.count }
    }()

    /// Best asset for one ingredient line ("200 g spaghetti", "4 garlic cloves, sliced"), or nil.
    static func asset(for text: String) -> String? {
        let words = normalize(text)
        guard !words.isEmpty else { return nil }
        if let hit = firstPhrase(in: words) { return hit.asset }
        for word in words.map(singular) {
            if allSet.contains(word) { return word }
            if let hit = aliases[word] { return hit }
        }
        return nil
    }

    /// A name the model returned, in any spelling, mapped onto the catalog; nil if nothing matches.
    static func canonical(_ name: String) -> String? {
        let snake = normalize(name).joined(separator: "_")
        if allSet.contains(snake) { return snake }
        return asset(for: name)
    }

    /// Every food asset a piece of step text mentions, in order of first mention, without vessels or duplicates.
    static func items(in text: String, limit: Int = 6) -> [String] {
        let words = normalize(text)
        var found: [String] = []
        var index = 0
        while index < words.count, found.count < limit {
            if let hit = firstPhrase(in: Array(words[index...]), anchored: true) {
                if !vesselAssets.contains(hit.asset), !found.contains(hit.asset) { found.append(hit.asset) }
                index += hit.length
            } else {
                let word = singular(words[index])
                if let asset = allSet.contains(word) ? word : aliases[word],
                   !vesselAssets.contains(asset), !found.contains(asset) { found.append(asset) }
                index += 1
            }
        }
        return found
    }

    // MARK: Text helpers

    /// Lowercase words with numbers, units and filler dropped: "200 g spaghetti" -> ["spaghetti"].
    static func normalize(_ text: String) -> [String] {
        let skip: Set<String> = ["g", "kg", "mg", "ml", "l", "oz", "lb", "lbs", "cup", "cups", "tbsp", "tsp", "tablespoon",
                                 "tablespoons", "teaspoon", "teaspoons", "pinch", "handful", "a", "an", "of", "the", "some",
                                 "large", "small", "medium", "fresh", "chopped", "sliced", "diced", "minced", "grated", "to", "taste"]
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !skip.contains($0) && Int($0) == nil && $0.rangeOfCharacter(from: .letters) != nil }
    }

    static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("es"), word.count > 4 {
            let stem = word.dropLast(2)
            if stem.hasSuffix("sh") || stem.hasSuffix("ch") || stem.hasSuffix("ss") || stem.hasSuffix("x") { return String(stem) }
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 3 { return String(word.dropLast()) }
        return word
    }

    /// The longest alias phrase found in the words (anywhere, or only at the start when anchored).
    private static func firstPhrase(in words: [String], anchored: Bool = false) -> (asset: String, length: Int)? {
        for phrase in phrases where phrase.words.count > 1 || anchored {
            let n = phrase.words.count
            guard n <= words.count else { continue }
            let starts = anchored ? [0] : Array(0...(words.count - n))
            for start in starts where Array(words[start..<(start + n)]) == phrase.words {
                return (phrase.asset, n)
            }
        }
        return nil
    }
}

// MARK: - What a step's scene shows

nonisolated struct SceneItem: Hashable, Sendable {
    /// Imageset name, or nil for a plain bowl with the label.
    var asset: String?
    var label: String
}

nonisolated extension RecipeStep {
    /// The model's vessel when it picked one, otherwise a guess from the words.
    var sceneVessel: Vessel {
        if let vessel { return vessel }
        let text = (title + " " + instruction + " " + imagePrompt).lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        if has("oven", "bake", "baking", "roast", "broil", "grill") { return .oven }
        if has("skillet", "frying pan", "sauté", "saute", "sear", "fry", "sizzl", "melt", "toss", "stir-fry", "wok") { return .pan }
        if has("pot", "boil", "simmer", "stock", "soup", "blanch", "steam", "braise", "stew") { return .pot }
        if has("board", "chop", "slice", "dice", "mince", "cut", "prep", "peel", "trim", "knife") { return .board }
        if has("serve", "plate", "garnish", "sprinkle over", "finish with") { return .plate }
        if has("bowl", "mix", "whisk", "combine", "marinate", "beat", "fold", "stir") { return .bowl }
        return .pan
    }

    /// The model's items when it picked some (unknown names go through the alias lookup and otherwise
    /// become a labelled plain bowl), otherwise every ingredient the step text mentions.
    var sceneItems: [SceneItem] {
        if let items, !items.isEmpty {
            var seen: Set<String> = []
            return items.compactMap { name in
                let label = name.replacingOccurrences(of: "_", with: " ")
                guard seen.insert(KitchenAssets.canonical(name) ?? label).inserted else { return nil }
                return SceneItem(asset: KitchenAssets.canonical(name), label: label)
            }
        }
        return KitchenAssets.items(in: title + ". " + instruction + ". " + imagePrompt)
            .map { SceneItem(asset: $0, label: $0.replacingOccurrences(of: "_", with: " ")) }
    }
}

nonisolated extension Recipe {
    /// One asset per ingredient line, by lookup; nil where nothing in the catalog fits.
    var ingredientAssets: [String?] { ingredients.map(KitchenAssets.asset(for:)) }
}
