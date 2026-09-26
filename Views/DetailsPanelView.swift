import SwiftUI

/// Top (tall) or left (wide) panel: the input form until there's a recipe,
/// then stats, the current step's words, the timer, and the step strip.
struct DetailsPanelView: View {
    @Environment(CookSession.self) private var session

    var body: some View {
        if session.phase == .ready, let recipe = session.recipe {
            RecipeDetails(recipe: recipe)
        } else {
            InputFormView()
        }
    }
}

private struct RecipeDetails: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    if let channel = recipe.channel {
                        Text(channel).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                StatsRow(recipe: recipe, minutesLeft: session.minutesLeft)

                switch session.slide {
                case .overview:
                    OverviewDetails(recipe: recipe)
                case .step(let index):
                    if recipe.steps.indices.contains(index) {
                        StepDetails(recipe: recipe, step: recipe.steps[index], index: index, count: recipe.steps.count)
                    }
                case .done:
                    DoneDetails(recipe: recipe)
                }

                StepStrip(steps: recipe.steps, current: session.currentStepIndex, done: session.slide == .done)
            }
            .padding()
        }
    }
}

private struct StatsRow: View {
    let recipe: Recipe
    let minutesLeft: Int

    var body: some View {
        // One row when the numbers fit; a 2x2 grid once type gets large.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { stats }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Stat(value: recipe.totalMinutes.cookTime, label: "Total")
                    Stat(value: recipe.handsOnMinutes.cookTime, label: "Hands-on")
                }
                GridRow {
                    Stat(value: minutesLeft.cookTime, label: "Left")
                    Stat(value: "\(recipe.servings)", label: "Serves")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recipe stats")
    }

    @ViewBuilder private var stats: some View {
        Stat(value: recipe.totalMinutes.cookTime, label: "Total")
        Stat(value: recipe.handsOnMinutes.cookTime, label: "Hands-on")
        Stat(value: minutesLeft.cookTime, label: "Left")
        Stat(value: "\(recipe.servings)", label: "Serves")
    }

    private struct Stat: View {
        let value: String, label: String
        var body: some View {
            VStack(spacing: 2) {
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label): \(value)")
        }
    }
}

private struct OverviewDetails: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gather the ingredients").font(.title3.weight(.semibold))
            Text(session.allIngredientsChecked
                 ? "Everything's out. Swipe to the first step when you're ready."
                 : "Tick them off on the slide as you set them out. \(session.checkedIngredients.count) of \(recipe.ingredients.count) so far.")
                .font(.body)
            if let url = recipe.sourceURL {
                Link(destination: url) { Label("Open the video", systemImage: "play.rectangle") }
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
    }
}

private struct StepDetails: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe
    let step: RecipeStep
    let index: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Step \(index + 1) of \(count)")
                    Spacer()
                    Label(step.minutes.cookTime, systemImage: step.isHandsOn ? "hand.raised" : "hourglass")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(index + 1) of \(count)")
                    Label(step.minutes.cookTime, systemImage: step.isHandsOn ? "hand.raised" : "hourglass")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(index + 1) of \(count), \(step.minutes.cookTime), \(step.isHandsOn ? "hands-on" : "waiting")")

            Text(step.title).font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            // Just what the cook needs in hand: the words themselves stay in read-aloud.
            NeedsRow(needs: StepNeeds.needs(for: step))

            if let timer = session.timer {
                StepTimerView(timer: timer)
            } else if step.needsTimer {
                timerButton.buttonStyle(.borderedProminent)
            } else {
                timerButton.buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .animation(.snappy, value: step.id)
    }

    /// Loud when the step is a wait, quiet otherwise; either way one tap starts the step's minutes.
    private var timerButton: some View {
        Button { session.startTimer() } label: {
            Label("\(step.minutes) min timer", systemImage: "timer")
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Start \(step.minutes) minute timer")
    }
}

/// Icons with a name and, when the step says so, an amount. Scrolls sideways when there are many.
private struct NeedsRow: View {
    let needs: [StepNeed]

    var body: some View {
        if needs.isEmpty {
            Text("Nothing to get out for this step.")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(needs.enumerated()), id: \.offset) { _, need in
                        VStack(spacing: 4) {
                            BowlView(asset: need.asset, label: need.asset == nil ? need.label : nil, width: 52)
                            Text(need.label.capitalized)
                                .font(.caption2.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            if let amount = need.amount {
                                Text(amount)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .frame(width: 76)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel([need.amount, need.label].compactMap { $0 }.joined(separator: " "))
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What you need")
        }
    }
}

private struct DoneDetails: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("That's the lot").font(.title3.weight(.semibold))
            Text("\(recipe.steps.count) steps, about \(recipe.totalMinutes.cookTime) all in, \(recipe.handsOnMinutes.cookTime) of it hands-on.")
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
    }
}

/// The steps are a real sequence, so numbered markers earn their place here.
private struct StepStrip: View {
    @Environment(CookSession.self) private var session
    let steps: [RecipeStep]
    let current: Int?
    let done: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        let reached = done || (current.map { index <= $0 } ?? false)
                        Button { session.goToStep(index) } label: {
                            VStack(spacing: 6) {
                                Text("\(index + 1)")
                                    .font(.callout.weight(.bold))
                                    .frame(width: 34, height: 34)
                                    .background(reached ? Theme.basil : Theme.card, in: .circle)
                                    .foregroundStyle(reached ? .white : .primary)
                                Text(step.title)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 72)
                                    .foregroundStyle(index == current ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityLabel("Step \(index + 1), \(step.title)")
                        .accessibilityAddTraits(index == current ? .isSelected : [])
                    }
                }
            }
            .onChange(of: current) { _, new in
                if let new { withAnimation { proxy.scrollTo(new, anchor: .center) } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All steps")
    }
}

extension Int {
    /// 75 -> "1:15", 0 -> "0:00"
    var clock: String { String(format: "%d:%02d", self / 60, self % 60) }
}
