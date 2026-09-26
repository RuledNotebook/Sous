import SwiftUI

struct AIPanelView: View {
    @Environment(CookSession.self) private var session

    var body: some View {
        switch session.phase {
        case .empty:
            StatusPanel(symbol: "frying.pan", title: "Pick a cooking video",
                        detail: "Choose one from Photos below. The steps, times and pictures show up here.")
        case .transcribing:
            StatusPanel(symbol: "waveform", title: "Listening to the video",
                        detail: "Turning the narration into a timestamped transcript.", busy: true)
        case .analyzing:
            StatusPanel(symbol: "sparkles", title: "Writing the steps",
                        detail: "Breaking the recipe into steps with real kitchen times.", busy: true)
        case .failed(let message):
            StatusPanel(symbol: "exclamationmark.triangle", title: "That video didn't work", detail: message)
        case .ready:
            if let recipe = session.recipe { RecipeGuide(recipe: recipe) }
        }
    }
}

// MARK: - Guide

private struct RecipeGuide: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe

    var body: some View {
        // Reads the panel height so the step picture can give way to the words
        // when the guide is short (closed pose), without touching the parent layout.
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(recipe.title)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    HandsFreeBar()
                    StatsRow(recipe: recipe, currentIndex: session.currentIndex)
                    if let step = session.currentStep {
                        CurrentStepCard(step: step, index: session.currentIndex, count: recipe.steps.count,
                                        artHeight: geo.size.height < 480 ? 130 : 210)
                    }
                    OtherTimersList()
                    StepStrip(steps: recipe.steps, current: session.currentIndex)
                    IngredientsList(ingredients: recipe.ingredients)
                }
                .padding()
            }
        }
    }
}

private struct StatsRow: View {
    let recipe: Recipe
    let currentIndex: Int

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
                    Stat(value: recipe.minutesLeft(from: currentIndex).cookTime, label: "Left")
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
        Stat(value: recipe.minutesLeft(from: currentIndex).cookTime, label: "Left")
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

private struct CurrentStepCard: View {
    @Environment(CookSession.self) private var session
    let step: RecipeStep
    let index: Int
    let count: Int
    var artHeight: CGFloat = 210

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepArt(step: step, image: session.stepImages[step.id])
                .frame(maxWidth: .infinity)
                .frame(height: artHeight)
                .clipShape(.rect(cornerRadius: 14))
                .accessibilityLabel(session.stepImages[step.id] == nil ? "Step picture loading" : "Picture: \(step.imagePrompt)")

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
            Text(step.instruction).font(.body)

            if !step.tip.isEmpty {
                Label(step.tip, systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Tip: \(step.tip)")
            }

            if let timer = session.currentStepTimer {
                StepTimerView(timer: timer)
            }

            // Prev / timer / next on one line when they fit, otherwise the timer gets its own line.
            ViewThatFits(in: .horizontal) {
                HStack {
                    previousButton
                    repeatButton
                    if step.needsTimer && session.currentStepTimer == nil { timerButton } else { Spacer() }
                    nextButton
                }
                VStack(spacing: 10) {
                    if step.needsTimer && session.currentStepTimer == nil { timerButton }
                    HStack {
                        previousButton
                        repeatButton
                        Spacer()
                        nextButton
                    }
                }
            }
        }
        .padding()
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .animation(.snappy, value: step.id)
    }

    private var previousButton: some View {
        Button { session.previous() } label: { Image(systemName: "chevron.left") }
            .buttonStyle(.bordered)
            .disabled(index == 0)
            .accessibilityLabel("Previous step")
    }

    private var repeatButton: some View {
        Button { session.repeatStep() } label: { Image(systemName: "arrow.counterclockwise") }
            .buttonStyle(.bordered)
            .accessibilityLabel("Repeat this step")
    }

    private var timerButton: some View {
        Button { session.startTimer() } label: {
            Label("Start \(step.minutes) min timer", systemImage: "timer")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Start \(step.minutes) minute timer")
    }

    private var nextButton: some View {
        Button { session.next() } label: {
            Label("Next step", systemImage: "chevron.right").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .disabled(index == count - 1)
    }
}

/// Generated/extracted image, or a quiet symbol while it loads.
private struct StepArt: View {
    let step: RecipeStep
    let image: UIImage?

    var body: some View {
        // The picture goes in an overlay so a fill-mode image can never push the
        // card wider than the panel; the tinted plate alone decides the size.
        Rectangle()
            .fill(Theme.basil.opacity(0.12))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.basil)
                }
            }
            .clipped()
            .animation(.easeInOut, value: image != nil)
    }

    private var symbol: String {
        let text = (step.title + " " + step.instruction).lowercased()
        switch true {
        case text.contains("bake") || text.contains("oven"):    return "oven"
        case text.contains("boil") || text.contains("simmer"):  return "flame"
        case text.contains("chop") || text.contains("slice") || text.contains("prep"): return "carrot"
        case text.contains("serve") || text.contains("plate"):  return "fork.knife"
        default:                                                return "frying.pan"
        }
    }
}

/// The steps are a real sequence, so numbered markers earn their place here.
private struct StepStrip: View {
    @Environment(CookSession.self) private var session
    let steps: [RecipeStep]
    let current: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        Button { session.goTo(i) } label: {
                            VStack(spacing: 6) {
                                Text("\(i + 1)")
                                    .font(.callout.weight(.bold))
                                    .frame(width: 34, height: 34)
                                    .background(i <= current ? Theme.basil : Theme.card, in: .circle)
                                    .foregroundStyle(i <= current ? .white : .primary)
                                Text(step.title)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 72)
                                    .foregroundStyle(i == current ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .accessibilityLabel("Step \(i + 1), \(step.title)")
                        .accessibilityAddTraits(i == current ? .isSelected : [])
                    }
                }
            }
            .onChange(of: current) { _, new in
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All steps")
    }
}

private struct IngredientsList: View {
    let ingredients: [String]
    var body: some View {
        DisclosureGroup("Ingredients (\(ingredients.count))") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ingredients, id: \.self) { Text($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .font(.subheadline)
    }
}

// MARK: - Status

private struct StatusPanel: View {
    let symbol: String, title: String, detail: String
    var busy = false

    var body: some View {
        VStack(spacing: 12) {
            if busy { ProgressView().controlSize(.large) }
            else { Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(Theme.basil) }
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
