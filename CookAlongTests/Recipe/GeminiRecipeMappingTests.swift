import Foundation
import Testing
@testable import CookAlong

@MainActor
struct GeminiRecipeMappingTests {
    let video = VideoMetadata(videoID: "4aZr5hZXP_s", title: "Chicken Teriyaki Casserole", channel: "TheCooknShare",
                              thumbnailURL: YouTubeLink.thumbnailURL(for: "4aZr5hZXP_s"))

    @Test func requestSendsTheWatchURLAsVideoInputAndForcesJSON() throws {
        let extractor = GeminiVideoRecipeExtractor(apiKey: "test-key", model: "gemini-3.8-flash")
        let request = try extractor.makeRequest(for: video)

        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        #expect(request.url?.query?.contains("key=") != true)   // the key never goes in the URL

        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let contents = try #require(body["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let fileData = try #require(parts.first?["fileData"] as? [String: Any])
        #expect(fileData["fileUri"] as? String == "https://www.youtube.com/watch?v=4aZr5hZXP_s")
        #expect(fileData["mimeType"] == nil)   // YouTube links need no MIME type
        #expect((parts.last?["text"] as? String)?.contains("Chicken Teriyaki Casserole") == true)

        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        let schema = try #require(config["responseSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "OBJECT")
        #expect(Set(schema["required"] as? [String] ?? []) == ["title", "servings", "difficulty", "ingredients", "durationSeconds", "steps"])
        let steps = try #require((schema["properties"] as? [String: Any])?["steps"] as? [String: Any])
        let step = try #require(steps["items"] as? [String: Any])
        #expect(Set(((step["properties"] as? [String: Any]) ?? [:]).keys) ==
                ["title", "instruction", "startSecond", "minutes", "isHandsOn", "needsTimer", "tip", "imagePrompt"])
        let system = try #require(body["systemInstruction"] as? [String: Any])
        #expect(((system["parts"] as? [[String: Any]])?.first?["text"] as? String)?.contains("startSecond") == true)
    }

    @Test func modelComesFromInfoPlistWithADefault() {
        #expect(GeminiVideoRecipeExtractor.fromInfoPlist(Bundle(for: Marker.self)) == nil)   // no key in the test bundle
        #expect(GeminiVideoRecipeExtractor(apiKey: "k").model == "gemini-3.8-flash")
        #expect(GeminiVideoRecipeExtractor.endpoint(model: "gemini-flash-latest").absoluteString.hasSuffix("models/gemini-flash-latest:generateContent"))
    }

    @Test func mapsAGenerateContentResponseToARecipe() throws {
        let recipeJSON = """
        {"title":"Chicken Teriyaki Casserole","servings":4,"difficulty":"easy","durationSeconds":200,
         "ingredients":["2 chicken breasts, cubed","1 cup teriyaki sauce","2 cups cooked rice","1 cup broccoli florets","rice"],
         "steps":[
          {"title":"Preheat the oven","instruction":"Heat the oven to 350 F.","startSecond":20,"minutes":10,"isHandsOn":false,"needsTimer":false,"tip":"","imagePrompt":"oven dial at 350"},
          {"title":"Cube the chicken","instruction":"Cut 2 chicken breasts into bite-size cubes.","startSecond":62,"minutes":4,"isHandsOn":true,"needsTimer":false,"tip":"Keep the pieces even.","imagePrompt":"cubed raw chicken on a board"},
          {"title":"Bake the casserole","instruction":"Bake for 25 minutes until bubbling.","startSecond":140,"minutes":1,"isHandsOn":false,"needsTimer":false,"tip":"","imagePrompt":"casserole in the oven"},
          {"title":"Serve","instruction":"Spoon over rice.","startSecond":900,"minutes":2,"isHandsOn":true,"needsTimer":false,"tip":"","imagePrompt":"plated casserole"}
         ]}
        """
        let escaped = recipeJSON.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        let response = """
        {"candidates":[{"content":{"parts":[{"text":"\(escaped)"}],"role":"model"},"finishReason":"STOP","index":0}],
         "usageMetadata":{"promptTokenCount":12345,"candidatesTokenCount":600,"totalTokenCount":12945},"modelVersion":"gemini-3.8-flash"}
        """
        let recipe = try GeminiVideoRecipeExtractor.parseRecipe(from: Data(response.utf8))

        #expect(recipe.title == "Chicken Teriyaki Casserole")
        #expect(recipe.servings == 4)
        #expect(recipe.steps.map(\.title) == ["Preheat the oven", "Cube the chicken", "Bake the casserole", "Serve"])
        // Shared sanity pass: the 3-second jump-cut bake is 25 real minutes with a timer, and the
        // start past the video's end is clamped to it; "rice" folds into "2 cups cooked rice".
        #expect(recipe.steps[2].minutes == 25)
        #expect(recipe.steps[2].needsTimer)
        #expect(recipe.steps[3].startSecond == 199)
        #expect(recipe.steps[1].tip == "Keep the pieces even.")
        #expect(recipe.ingredients.count == 4)
        let starts = recipe.steps.map(\.startSecond)
        #expect(zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func reportsBlocksTruncationAndGarbage() {
        let blocked = #"{"promptFeedback":{"blockReason":"SAFETY"}}"#
        #expect(throws: RecipeSourceError.cloud("Gemini declined this video (SAFETY)")) {
            try GeminiVideoRecipeExtractor.parseRecipe(from: Data(blocked.utf8))
        }
        let cut = #"{"candidates":[{"content":{"parts":[{"text":"{\"title\":"}]},"finishReason":"MAX_TOKENS"}]}"#
        #expect(throws: RecipeSourceError.cloud("the answer was cut off (MAX_TOKENS)")) {
            try GeminiVideoRecipeExtractor.parseRecipe(from: Data(cut.utf8))
        }
        #expect(throws: RecipeSourceError.cloud("not a generateContent response")) {
            try GeminiVideoRecipeExtractor.parseRecipe(from: Data("<html>".utf8))
        }
        #expect(throws: RecipeSourceError.cloud("Gemini returned no answer")) {
            try GeminiVideoRecipeExtractor.parseRecipe(from: Data(#"{"candidates":[]}"#.utf8))
        }
        let wrongShape = #"{"candidates":[{"content":{"parts":[{"text":"{\"hello\":1}"}]},"finishReason":"STOP"}]}"#
        #expect(throws: RecipeSourceError.self) {
            try GeminiVideoRecipeExtractor.parseRecipe(from: Data(wrongShape.utf8))
        }
    }

    @Test func unknownDurationLeavesTimestampsUncapped() throws {
        let payload = try JSONDecoder().decode(GeminiVideoRecipeExtractor.Payload.self, from: Data("""
        {"title":"X","servings":2,"difficulty":"hard","ingredients":[],
         "steps":[{"title":"a","instruction":"a","startSecond":30,"minutes":1,"isHandsOn":true,"needsTimer":false},
                  {"title":"b","instruction":"b","startSecond":3000,"minutes":1,"isHandsOn":true,"needsTimer":false}]}
        """.utf8))
        let recipe = GeminiVideoRecipeExtractor.recipe(from: payload)
        #expect(recipe.steps.map(\.startSecond) == [30, 3000])
        #expect(recipe.steps.map(\.title) == ["A", "B"])
    }
}

private final class Marker {}
