import SwiftUI

/// Bottom (tall) or left-under-the-video (wide) panel: the input form until there's a recipe,
/// then a compact cook bar with only what the cook needs in hand: the step's ingredients with
/// their amounts (tap to tick off), the timer, and a replay of this step's part of the video.
/// The recipe's words live on the slides and in the video; nothing is repeated here.
struct DetailsPanelView: View {
    @Environment(CookSession.self) private var session

    var body: some View {
        if session.phase == .ready, let recipe = session.recipe {
            CookBar(recipe: recipe)
        } else {
            InputFormView()
        }
    }
}

private struct CookBar: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch session.slide {
            case .overview:
                OverviewBar(recipe: recipe)
            case .step(let index):
                if recipe.steps.indices.contains(index) {
                    StepBar(recipe: recipe, step: recipe.steps[index], index: index, count: recipe.steps.count)
                }
            case .done:
                DoneBar(recipe: recipe)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: session.slide)
    }
}

// MARK: - Ingredients slide

private struct OverviewBar: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.checkedIngredients.count) of \(recipe.ingredients.count) out")
                    .font(.headline).monospacedDigit()
                Text("Serves \(recipe.servings) · \(recipe.totalMinutes.cookTime), \(recipe.handsOnMinutes.cookTime) hands-on")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { session.next() } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Start with step 1")
        }
    }
}

// MARK: - Step slide

private struct StepBar: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe
    let step: RecipeStep
    let index: Int
    let count: Int
    /// Ticks for needs that aren't one of the recipe's ingredient lines (a splash of water, say).
    @State private var localTicks: Set<String> = []

    var body: some View {
        let needs = StepNeeds.needs(for: step)
        VStack(alignment: .leading, spacing: 10) {
            if needs.isEmpty {
                Text("Nothing to get out for this step.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(needs.enumerated()), id: \.offset) { _, need in
                            let ingredientIndex = ingredientIndex(for: need)
                            let ticked = ingredientIndex.map { session.checkedIngredients.contains($0) } ?? localTicks.contains(key(need))
                            NeedChip(need: need, ticked: ticked) {
                                if let ingredientIndex {
                                    session.toggleIngredient(ingredientIndex)
                                } else if localTicks.contains(key(need)) {
                                    localTicks.remove(key(need))
                                } else {
                                    localTicks.insert(key(need))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("What you need for this step")
            }

            HStack(spacing: 10) {
                if let timer = session.timer {
                    StepTimerView(timer: timer)
                        .layoutPriority(1)
                } else if step.needsTimer {
                    timerButton.buttonStyle(.borderedProminent)
                } else {
                    timerButton.buttonStyle(.bordered)
                }

                if recipe.videoID != nil {
                    Button { session.repeatStep() } label: {
                        Label("Watch", systemImage: "arrow.counterclockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Play this step's part of the video again")
                }

                Spacer(minLength: 0)

                Label("\(index + 1)/\(count)", systemImage: step.isHandsOn ? "hand.raised" : "hourglass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("Step \(index + 1) of \(count), \(step.isHandsOn ? "hands-on" : "waiting")")
            }
            .font(.subheadline)
        }
    }

    private var timerButton: some View {
        Button { session.startTimer() } label: {
            Label("\(step.minutes) min", systemImage: "timer")
        }
        .accessibilityLabel("Start \(step.minutes) minute timer")
    }

    private func key(_ need: StepNeed) -> String { "\(step.id)-\(need.label.lowercased())" }

    /// The recipe ingredient line this need stands for, so a tick here also ticks the checklist.
    private func ingredientIndex(for need: StepNeed) -> Int? {
        let assets = recipe.ingredientAssets
        if let asset = need.asset, let i = assets.firstIndex(of: asset) { return i }
        let label = need.label.lowercased()
        return recipe.ingredients.firstIndex { $0.lowercased().contains(label) }
    }
}

/// Icon, name and amount; tap to tick it off.
private struct NeedChip: View {
    let need: StepNeed
    let ticked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 3) {
                BowlView(asset: need.asset, label: need.asset == nil ? need.label : nil, width: 48)
                    .overlay(alignment: .topTrailing) {
                        if ticked {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.white, Theme.basil)
                                .offset(x: 4, y: -2)
                        }
                    }
                Text(need.label.capitalized)
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .strikethrough(ticked)
                    .foregroundStyle(ticked ? .secondary : .primary)
                if let amount = need.amount {
                    Text(amount)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(width: 74)
            .opacity(ticked ? 0.65 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: ticked)
        .accessibilityLabel([need.amount, need.label].compactMap { $0 }.joined(separator: " "))
        .accessibilityValue(ticked ? "checked" : "not checked")
        .accessibilityHint("Double tap to \(ticked ? "uncheck" : "check")")
    }
}

// MARK: - Done slide

private struct DoneBar: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("That's the lot").font(.headline)
                Text("\(recipe.steps.count) steps, about \(recipe.totalMinutes.cookTime).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("New recipe") { session.reset() }
                .buttonStyle(.borderedProminent)
        }
    }
}

extension Int {
    /// 75 -> "1:15", 0 -> "0:00"
    var clock: String { String(format: "%d:%02d", self / 60, self % 60) }
}
