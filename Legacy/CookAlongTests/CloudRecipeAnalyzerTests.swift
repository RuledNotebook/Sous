import Foundation
import Testing
@testable import CookAlong

@MainActor
struct CloudRecipeAnalyzerTests {
    @Test func infoPlistKeyIsRequired() {
        // The test bundle has no ANTHROPIC_API_KEY, so the cloud analyzer must not be configured from it.
        #expect(CloudRecipeAnalyzer.fromInfoPlist(Bundle(for: Marker.self)) == nil)
    }

    @Test func requestUsesStructuredJSONOutputAndTheRenderedTranscript() throws {
        let analyzer = CloudRecipeAnalyzer(apiKey: "sk-test")
        let request = try analyzer.makeRequest(transcript: SampleTranscripts.bakedSalmon, videoDuration: 66, refusalFallback: true)

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5")
        #expect(body["fallbacks"] as? String == "default")
        let format = try #require((body["output_config"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(Set(schema["required"] as? [String] ?? []) == ["title", "servings", "difficulty", "ingredients", "steps"])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? String)
        #expect(content.contains("[40s] Into the oven for 25 minutes."))
        #expect(content.contains("66 seconds long"))
        #expect((body["system"] as? String)?.contains("startSecond") == true)

        let plain = try analyzer.makeRequest(transcript: SampleTranscripts.bakedSalmon, videoDuration: 66, refusalFallback: false)
        #expect(plain.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let plainBody = try #require(JSONSerialization.jsonObject(with: plain.httpBody ?? Data()) as? [String: Any])
        #expect(plainBody["fallbacks"] == nil)
    }

    @Test func parsesAMessagesResponseIntoARecipe() throws {
        let recipeJSON = """
        {"title":"Baked salmon","servings":2,"difficulty":"easy",
         "ingredients":["2 salmon fillets","olive oil","1 lemon","salt","pepper","lemon"],
         "steps":[
          {"title":"Preheat the oven","instruction":"Heat the oven to 200 degrees.","startSecond":6,"minutes":10,"isHandsOn":false,"needsTimer":false,"tip":"","imagePrompt":"oven dial at 200"},
          {"title":"Season the salmon","instruction":"Oil, salt, pepper and lemon slices on the fillets.","startSecond":12,"minutes":3,"isHandsOn":true,"needsTimer":false,"tip":"Pat the fish dry first.","imagePrompt":"seasoned salmon on a tray"},
          {"title":"Bake the salmon","instruction":"Bake for 25 minutes.","startSecond":40,"minutes":1,"isHandsOn":false,"needsTimer":false,"tip":"","imagePrompt":"baked salmon"},
          {"title":"Rest and serve","instruction":"Rest five minutes, serve with the roasted lemon.","startSecond":900,"minutes":5,"isHandsOn":false,"needsTimer":true,"tip":"","imagePrompt":"plated salmon"}
         ]}
        """
        let escaped = recipeJSON.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        let response = """
        {"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-5",
         "content":[{"type":"text","text":"\(escaped)"}],
         "stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}
        """
        let recipe = try CloudRecipeAnalyzer.parseRecipe(from: Data(response.utf8), videoDuration: 66)

        #expect(recipe.title == "Baked salmon")
        #expect(recipe.servings == 2)
        #expect(recipe.steps.count == 4)
        #expect(recipe.steps.map(\.title) == ["Preheat the oven", "Season the salmon", "Bake the salmon", "Rest and serve"])
        // Shared sanity pass: the jump-cut "1 minute" bake becomes 25, and the out-of-range start is clamped.
        #expect(recipe.steps[2].minutes == 25)
        #expect(recipe.steps[2].needsTimer)
        #expect(recipe.steps[3].videoStart == 65)
        #expect(recipe.steps[1].tip == "Pat the fish dry first.")
        // "lemon" is folded into "1 lemon".
        #expect(recipe.ingredients.filter { $0.lowercased().contains("lemon") }.count == 1)
    }

    @Test func rejectsRefusalsTruncationAndGarbage() {
        let refusal = #"{"content":[],"stop_reason":"refusal"}"#
        #expect(throws: RecipeAnalysisError.refused("safety refusal")) {
            try CloudRecipeAnalyzer.parseRecipe(from: Data(refusal.utf8), videoDuration: 10)
        }
        let cut = #"{"content":[{"type":"text","text":"{\"title\":"}],"stop_reason":"max_tokens"}"#
        #expect(throws: RecipeAnalysisError.self) {
            try CloudRecipeAnalyzer.parseRecipe(from: Data(cut.utf8), videoDuration: 10)
        }
        #expect(throws: RecipeAnalysisError.badResponse("not a Messages API response")) {
            try CloudRecipeAnalyzer.parseRecipe(from: Data("<html>".utf8), videoDuration: 10)
        }
        let wrongShape = #"{"content":[{"type":"text","text":"{\"hello\":1}"}],"stop_reason":"end_turn"}"#
        #expect(throws: RecipeAnalysisError.self) {
            try CloudRecipeAnalyzer.parseRecipe(from: Data(wrongShape.utf8), videoDuration: 10)
        }
    }

    @Test func stripsCodeFences() {
        #expect(CloudRecipeAnalyzer.stripFences("```json\n{\"a\":1}\n```") == "{\"a\":1}")
        #expect(CloudRecipeAnalyzer.stripFences("  {\"a\":1}  ") == "{\"a\":1}")
    }

    @Test func routerSendsLongVideosToTheCloudAndShortOnesOnDevice() async throws {
        let cloud = RecordingAnalyzer(name: "cloud")
        let device = RecordingAnalyzer(name: "device")
        var router = RoutingRecipeAnalyzer(onDevice: device, cloud: cloud)
        router.longVideoSeconds = 60

        _ = try await router.recipe(from: SampleTranscripts.bakedSalmon, videoDuration: 30)
        #expect(device.calls == 1 && cloud.calls == 0)

        _ = try await router.recipe(from: SampleTranscripts.bakedSalmon, videoDuration: 3_000)
        #expect(device.calls == 1 && cloud.calls == 1)

        // Cloud failure falls back to on-device.
        cloud.error = RecipeAnalysisError.http(529, "overloaded")
        _ = try await router.recipe(from: SampleTranscripts.bakedSalmon, videoDuration: 3_000)
        #expect(device.calls == 2 && cloud.calls == 2)

        // No on-device, no cloud: the demo fallback.
        let bare = RoutingRecipeAnalyzer(onDevice: nil, cloud: nil, fallback: RecordingAnalyzer(name: "mock"))
        let r = try await bare.recipe(from: SampleTranscripts.bakedSalmon, videoDuration: 30)
        #expect(r.title == "mock")
    }
}

private final class Marker {}

@MainActor
final class RecordingAnalyzer: RecipeAnalyzer {
    let name: String
    var calls = 0
    var error: (any Error)?
    init(name: String) { self.name = name }
    func recipe(from transcript: [TranscriptLine], videoDuration: Double) async throws -> Recipe {
        calls += 1
        if let error { throw error }
        return Recipe(title: name, servings: 1, difficulty: "easy", ingredients: [], steps: [])
    }
}
