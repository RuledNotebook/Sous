import SwiftUI

/// Ingredients slide, one slide per step, done slide. Swipe or use the arrows.
struct SlideshowView: View {
    @Environment(CookSession.self) private var session
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if session.phase == .ready {
                SlideshowBar()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var stage: some View {
        switch session.phase {
        case .ready:
            carousel
        case .working:
            StatusSlide(symbol: "sparkles", title: "Making your slideshow",
                        detail: "Reading the video and writing the steps.", busy: true)
        case .failed(let message):
            StatusSlide(symbol: "exclamationmark.triangle", title: "That didn't work", detail: message)
        case .empty:
            StatusSlide(symbol: "rectangle.stack", title: "Your slideshow shows up here",
                        detail: "Paste a YouTube cooking video, or try the demo.")
        }
    }

    /// Slides sit side by side and slide over; only the neighbours of the current one exist.
    private var carousel: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let current = session.slideIndex
            ZStack {
                ForEach(Array(session.slides.enumerated()), id: \.element) { index, slide in
                    if abs(index - current) <= 1 {
                        SlideView(slide: slide)
                            .frame(width: width, height: geo.size.height)
                            .offset(x: CGFloat(index - current) * width + dragOffset)
                            .accessibilityHidden(index != current)
                    }
                }
            }
            .animation(.snappy, value: current)
            .animation(.interactiveSpring, value: dragOffset)
        }
        .clipShape(.rect(cornerRadius: 18))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .updating($dragOffset) { value, state, _ in state = value.translation.width }
                .onEnded { value in
                    if value.translation.width < -60 { session.next() }
                    else if value.translation.width > 60 { session.previous() }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Slideshow")
        .accessibilityAction(named: "Next slide") { session.next() }
        .accessibilityAction(named: "Previous slide") { session.previous() }
    }
}

// MARK: - Slides

private struct SlideView: View {
    @Environment(CookSession.self) private var session
    let slide: CookSession.Slide

    var body: some View {
        if let recipe = session.recipe {
            switch slide {
            case .overview:
                OverviewSlide(recipe: recipe)
            case .step(let index):
                if recipe.steps.indices.contains(index) {
                    let step = recipe.steps[index]
                    StepSlide(step: step, index: index, count: recipe.steps.count, isActive: session.slide == slide)
                }
            case .done:
                DoneSlide(recipe: recipe)
            }
        }
    }
}

/// Thumbnail, title, and the ingredient checklist.
private struct OverviewSlide: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Thumbnail(url: recipe.thumbnailURL)
                    .frame(width: 128, height: 72)
                    .clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    if let channel = recipe.channel {
                        Text(channel).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Serves \(recipe.servings) · \(recipe.difficulty.capitalized)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Text("Ingredients").font(.headline)
                Spacer()
                Text("\(session.checkedIngredients.count) of \(recipe.ingredients.count)")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
            }

            ScrollView {
                IngredientBowlGrid(ingredients: recipe.ingredients, checked: session.checkedIngredients) {
                    session.toggleIngredient($0)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card)
    }
}

struct IngredientRow: View {
    let text: String
    let checked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Theme.accent : .secondary)
                Text(text)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: checked)
        .accessibilityValue(checked ? "checked" : "not checked")
        .accessibilityHint("Double tap to \(checked ? "uncheck" : "check")")
    }
}

/// The step's scene (vessel and ingredients), title over a gradient, "Step n of m".
private struct StepSlide: View {
    let step: RecipeStep
    let index: Int
    let count: Int
    var isActive = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            StepSceneView(step: step, isActive: isActive)

            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.85)],
                           startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)

            heading
                .padding(16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count), \(step.title). \(step.instruction)")
    }

    /// Step number, title, and the one thing to do now, so the slide alone is enough to cook from.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(index + 1) of \(count)")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .opacity(0.85)
            Text(step.title)
                .font(.title.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(step.instruction)
                .font(.title3)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DoneSlide: View {
    @Environment(CookSession.self) private var session
    let recipe: Recipe

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("All done").font(.title2.weight(.bold))
            Text("Enjoy your \(recipe.title.lowercased()).")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { doneButtons }
                VStack(spacing: 10) { doneButtons }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card)
    }

    @ViewBuilder private var doneButtons: some View {
        Button("Back to the start") { session.go(to: .overview) }
            .buttonStyle(.bordered)
        Button("New recipe") { session.reset() }
            .buttonStyle(.borderedProminent)
            .tint(Theme.actionFill)
    }
}

/// YouTube thumbnail with a placeholder while it loads (or when there is none).
private struct Thumbnail: View {
    let url: URL?

    var body: some View {
        Rectangle()
            .fill(Theme.accent.opacity(0.12))
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo").foregroundStyle(Theme.accent)
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct StatusSlide: View {
    let symbol: String, title: String, detail: String
    var busy = false

    var body: some View {
        VStack(spacing: 12) {
            if busy { ProgressView().controlSize(.large) }
            else { Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(Theme.accent) }
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Controls under the slides

struct SlideshowBar: View {
    @Environment(CookSession.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var compact = false
    var onShowVideo: (() -> Void)? = nil

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { session.previous() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!session.canGoBack)
                    .accessibilityLabel("Previous slide")

                Spacer(minLength: 0)

                if compact && dynamicTypeSize.isAccessibilitySize {
                    voiceToggle.labelStyle(.iconOnly)
                } else {
                    voiceToggle
                }

                if compact || session.recipe?.videoID == nil {
                    Toggle(isOn: $session.readAloud) {
                        Label("Read aloud", systemImage: session.readAloud ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Read each slide aloud")
                }

                Spacer(minLength: 0)

                Button { session.next() } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.actionFill)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!session.canGoForward)
                    .accessibilityLabel("Next slide")
            }
            .font(.subheadline)

            HStack(spacing: 8) {
                if compact {
                    Menu {
                        Button("Ingredients") { session.go(to: .overview) }
                        ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                            Button("Step \(index + 1): \(step.title)") { session.goToStep(index) }
                        }
                        Button("Done") { session.go(to: .done) }
                    } label: {
                        Label(position, systemImage: "list.number")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Jump to a slide, currently \(position)")
                } else {
                    Text(position).monospacedDigit()
                }
                if !compact || session.voiceEnabled {
                    Spacer(minLength: 8)
                    VoiceStatusBar()
                }
                if let onShowVideo, session.recipe?.videoID != nil {
                    Spacer(minLength: 8)
                    Button(action: onShowVideo) {
                        Image(systemName: "play.rectangle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Show cooking video")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var voiceToggle: some View {
        Toggle(isOn: Binding(get: { session.voiceEnabled }, set: { session.setVoice(enabled: $0) })) {
            Label("Listen", systemImage: session.voice.status.isListening ? "mic.fill" : "mic")
        }
        .toggleStyle(.button)
        .tint(session.voice.status.isListening ? .red : Theme.accent)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Voice control")
    }

    private var position: String {
        switch session.slide {
        case .overview: "Ingredients"
        case .step(let index): "Step \(index + 1) of \(session.steps.count)"
        case .done: "Done"
        }
    }
}

/// One line that says whether we're listening and what we last heard.
private struct VoiceStatusBar: View {
    @Environment(CookSession.self) private var session

    var body: some View {
        let status = session.voice.status
        HStack(spacing: 6) {
            Circle()
                .fill(status.isListening ? Color.red : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(text).lineLimit(1)
        }
        .animation(.snappy, value: status)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice status: \(text)")
    }

    private var text: String {
        let status = session.voice.status
        if session.speaker.isSpeaking { return "Speaking…" }
        if status.isListening, !session.voice.heard.isEmpty { return "…\(session.voice.heard)" }
        if status.isListening { return "Say: next · back · skip ahead 10 seconds · pause · step 3 · what do I need · how long" }
        return session.voiceEnabled ? status.label : "Mic off"
    }
}
