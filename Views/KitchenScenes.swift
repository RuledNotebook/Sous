import SwiftUI

// Bundled Kitchen art (Microsoft Fluent Emoji, MIT), with optional cached scene backgrounds.

/// One designed set: every bowl, vessel and gap uses these numbers.
enum KitchenStyle {
    static let bowlWidth: CGFloat = 64
    static let gridSpacing: CGFloat = 14
    static let warmTop = Color(red: 0.996, green: 0.965, blue: 0.914)
    static let warmBottom = Color(red: 0.965, green: 0.878, blue: 0.784)
    static let shadow = Color.black.opacity(0.14)
    static let boardWood = Color(red: 0.87, green: 0.72, blue: 0.53)
}

/// A small white bowl with an ingredient sitting in it, or just a name when there is no art for it.
struct BowlView: View {
    var asset: String?
    var label: String? = nil
    var width: CGFloat = KitchenStyle.bowlWidth

    var body: some View {
        let rim = width * 0.56
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(.white)
                .frame(width: width, height: rim)
                .overlay(Ellipse().stroke(Color.black.opacity(0.06), lineWidth: 1))
                .shadow(color: KitchenStyle.shadow, radius: width * 0.09, y: width * 0.06)
            if let asset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width * 0.6, height: width * 0.6)
                    .padding(.bottom, rim * 0.42)
            } else if let label {
                Text(label)
                    .font(.system(size: max(9, width * 0.15), weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: width * 0.8)
                    .padding(.bottom, rim * 0.28)
            }
        }
        .frame(width: width, height: width * 0.9, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// Vertical offset of the ingredient's centre from the bowl view's centre (it sits above the rim).
    static func ingredientOffset(width: CGFloat) -> CGFloat {
        let rim = width * 0.56
        let frameHeight = width * 0.9
        let imageBottom = frameHeight - rim * 0.42
        return imageBottom - width * 0.3 - frameHeight / 2
    }
}

/// The pot, pan, bowl, board, oven or plate a step happens in, drawn large.
struct VesselView: View {
    let vessel: Vessel
    var size: CGFloat = 160

    var body: some View {
        ZStack {
            switch vessel {
            case .pot:   art("pot_of_food")
            case .pan:   art("shallow_pan_of_food")
            case .bowl:  art("bowl_with_spoon")
            case .plate: art("fork_and_knife_with_plate")
            case .board:
                RoundedRectangle(cornerRadius: size * 0.08)
                    .fill(KitchenStyle.boardWood)
                    .frame(width: size, height: size * 0.62)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.08).stroke(Color.black.opacity(0.1), lineWidth: 1))
                art("kitchen_knife", scale: 0.66)
                    .rotationEffect(.degrees(-18))
                    .offset(y: -size * 0.04)
            case .oven:
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(Color(white: 0.38))
                    .frame(width: size, height: size * 0.82)
                RoundedRectangle(cornerRadius: size * 0.06)
                    .fill(Color(white: 0.16))
                    .frame(width: size * 0.78, height: size * 0.48)
                    .offset(y: size * 0.07)
                HStack(spacing: size * 0.08) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(white: 0.75)).frame(width: size * 0.07) }
                }
                .offset(y: -size * 0.3)
                art("fire", scale: 0.36)
                    .offset(y: size * 0.07)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: KitchenStyle.shadow, radius: size * 0.06, y: size * 0.05)
        .accessibilityHidden(true)
    }

    private func art(_ name: String, scale: CGFloat = 1) -> some View {
        Image(name).resizable().scaledToFit().frame(width: size * scale, height: size * scale)
    }
}

/// Step slide scene: warm background, the vessel in the middle (a generated picture when `SceneArtStore`
/// has one, else the bundled art) and the step's ingredients in bowls on a symmetric arc above it.
///
/// Motion, in order, once the slide is current: the vessel settles in; the bowls rise into place from the
/// middle outwards; then the ingredients go in one at a time, each along a smooth arc into the vessel's
/// mouth, with a single ripple where it lands. Tap a bowl to send that one in, tap the vessel to replay.
struct StepSceneView: View {
    let step: RecipeStep
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var dropped: Set<Int> = []
    @State private var ripples: [Ripple] = []
    @State private var vesselPulse = false
    @State private var sequence: Task<Void, Never>?
    private let art = SceneArtStore.shared

    var body: some View {
        GeometryReader { geo in
            let layout = SceneLayout(size: geo.size, count: min(step.sceneItems.count, 6), vessel: step.sceneVessel)
            let items = Array(step.sceneItems.prefix(6))
            let key = SceneArtKey(step: step)
            ZStack {
                LinearGradient(colors: [KitchenStyle.warmTop, KitchenStyle.warmBottom], startPoint: .top, endPoint: .bottom)

                Group {
                    if let picture = art.image(for: key) {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFit()
                            .frame(width: layout.vesselSize * 1.25, height: layout.vesselSize * 1.25)
                            .shadow(color: KitchenStyle.shadow, radius: layout.vesselSize * 0.06, y: layout.vesselSize * 0.05)
                            .transition(.opacity)
                    } else {
                        VesselView(vessel: step.sceneVessel, size: layout.vesselSize)
                    }
                }
                .scaleEffect(vesselPulse ? 1.03 : 1)
                .animation(.spring(duration: 0.35, bounce: 0.45), value: vesselPulse)
                .position(layout.center)
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
                .animation(.smooth(duration: 0.45), value: appeared)
                .animation(.easeInOut(duration: 0.35), value: art.images.count)
                .contentShape(Circle().scale(0.8))
                .onTapGesture { replay(items.count) }
                .accessibilityHidden(true)

                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let home = layout.bowlCenter(index)
                    let delay = layout.riseDelay(index)
                    BowlView(asset: nil, label: item.asset == nil ? item.label : nil, width: layout.bowl)
                        .position(home)
                        .offset(y: appeared ? 0 : 16)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(duration: 0.5, bounce: 0.15).delay(delay), value: appeared)
                        .onTapGesture { drop(index, of: items.count) }
                    if let asset = item.asset {
                        FlyingIngredient(asset: asset, size: layout.bowl * 0.6,
                                         from: layout.ingredientSlot(index), to: layout.landing(index),
                                         flying: dropped.contains(index), vanishes: layout.swallows,
                                         duration: reduceMotion ? 0.01 : 0.55)
                            .offset(y: appeared ? 0 : 16)
                            .opacity(appeared ? 1 : 0)
                            .animation(.spring(duration: 0.5, bounce: 0.15).delay(delay), value: appeared)
                            .allowsHitTesting(false)
                    }
                }

                ForEach(ripples) { ripple in
                    RippleView(kind: ripple.kind, width: layout.vesselSize * 0.42).position(layout.mouth)
                }
            }
        }
        .clipped()
        .onChange(of: isActive, initial: true) { _, active in
            appeared = active
            if active { replay(step.sceneItems.prefix(6).count) } else { stop() }
        }
        .onDisappear { stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sceneLabel)
        .accessibilityAction(named: "Show the ingredients go in") { replay(step.sceneItems.prefix(6).count) }
    }

    private var sceneLabel: String {
        let names = step.sceneItems.prefix(6).map(\.label)
        return names.isEmpty ? "\(step.sceneVessel.rawValue)" : "\(names.joined(separator: ", ")) into the \(step.sceneVessel.rawValue)"
    }

    private func stop() {
        sequence?.cancel()
        sequence = nil
        dropped = []
        ripples = []
        vesselPulse = false
    }

    /// Everything back in its bowl, then in they go, left to right, one at a time.
    private func replay(_ count: Int) {
        stop()
        guard count > 0 else { return }
        sequence = Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 950))
            for index in 0..<count {
                guard !Task.isCancelled else { return }
                drop(index, of: count)
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 650))
            }
        }
    }

    private func drop(_ index: Int, of count: Int) {
        guard !dropped.contains(index) else { return }
        dropped.insert(index)
        let items = Array(step.sceneItems.prefix(6))
        let ripple = Ripple(kind: Ripple.kind(for: items.indices.contains(index) ? items[index].asset : nil, in: step.sceneVessel))
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 470))   // the ingredient reaches the mouth
            guard !Task.isCancelled else { return }
            ripples.append(ripple)
            vesselPulse = true
            try? await Task.sleep(for: .milliseconds(140))
            vesselPulse = false
            try? await Task.sleep(for: .milliseconds(600))
            ripples.removeAll { $0.id == ripple.id }
        }
    }
}

/// Where everything sits, computed once per slide size so every step looks like the same set.
/// Bowls sit on an elliptical arc centred straight above the vessel, evenly spaced and mirrored.
struct SceneLayout {
    let size: CGSize
    let count: Int
    let vessel: Vessel
    let vesselSize: CGFloat
    let bowl: CGFloat
    let center: CGPoint

    init(size: CGSize, count: Int, vessel: Vessel) {
        self.size = size
        self.count = count
        self.vessel = vessel
        let unit = min(size.width, size.height)
        vesselSize = unit * 0.40
        bowl = min(max(unit * 0.16, 44), 72)
        center = CGPoint(x: size.width / 2, y: size.height * 0.5)
    }

    /// Angular spacing between neighbouring bowls, in degrees; the arc never exceeds 150°.
    private var spacing: Double { count <= 1 ? 0 : min(36, 150 / Double(count - 1)) }

    private var radii: (x: CGFloat, y: CGFloat) {
        var rx = vesselSize * 0.62 + bowl * 0.85
        let ry = vesselSize * 0.55 + bowl * 0.6
        // Keep the outermost bowls inside the slide with a small margin.
        let halfSpan = CGFloat(sin(spacing * Double(count - 1) / 2 * .pi / 180))
        if count > 1, rx * halfSpan > size.width / 2 - bowl / 2 - 10 {
            rx = (size.width / 2 - bowl / 2 - 10) / halfSpan
        }
        return (rx, ry)
    }

    func bowlCenter(_ index: Int) -> CGPoint {
        let offset = Double(index) - Double(count - 1) / 2
        let angle = (270 + offset * spacing) * .pi / 180
        let r = radii
        let y = max(bowl * 0.5 + 10, center.y + r.y * CGFloat(sin(angle)))
        return CGPoint(x: center.x + r.x * CGFloat(cos(angle)), y: y)
    }

    /// Where the ingredient rests inside its bowl (matches `BowlView`).
    func ingredientSlot(_ index: Int) -> CGPoint {
        let home = bowlCenter(index)
        return CGPoint(x: home.x, y: home.y + BowlView.ingredientOffset(width: bowl))
    }

    /// The point an ingredient disappears into, per vessel.
    var mouth: CGPoint {
        let dy: CGFloat
        switch vessel {
        case .pot:   dy = -0.22
        case .bowl:  dy = -0.12
        case .pan:   dy = -0.05
        case .board: dy = -0.05
        case .plate: dy = 0
        case .oven:  dy = 0.02
        }
        return CGPoint(x: center.x, y: center.y + vesselSize * dy)
    }

    /// Pots, pans, bowls and ovens swallow what goes in; plates and boards keep the food in view.
    var swallows: Bool {
        switch vessel {
        case .pot, .pan, .bowl, .oven: true
        case .plate, .board: false
        }
    }

    /// Where an ingredient ends up: the mouth, or a small symmetric cluster on a plate or board.
    func landing(_ index: Int) -> CGPoint {
        guard !swallows, count > 1 else { return mouth }
        let angle = (-90 + 360 * Double(index) / Double(count)) * .pi / 180
        let r = vesselSize * (vessel == .plate ? 0.24 : 0.22)
        return CGPoint(x: mouth.x + r * CGFloat(cos(angle)), y: mouth.y + r * 0.6 * CGFloat(sin(angle)))
    }

    /// Bowls rise in from the middle outwards, so the arc grows symmetrically.
    func riseDelay(_ index: Int) -> Double {
        0.15 + abs(Double(index) - Double(count - 1) / 2) * 0.07
    }
}

/// An ingredient that rests in its bowl until `flying`, then travels along a smooth arc to its landing point,
/// shrinking as it goes and, for vessels that swallow it, fading as it lands. Snaps back when `flying` turns off.
struct FlyingIngredient: View {
    let asset: String
    let size: CGFloat
    let from: CGPoint
    let to: CGPoint
    let flying: Bool
    /// True: fades away as it lands (into a pot). False: stays on the plate at a smaller size.
    var vanishes = true
    var duration = 0.55

    var body: some View {
        // Anchored at the bowl; the flight is a relative offset so the animator's own size never matters.
        KeyframeAnimator(initialValue: 0.0, trigger: flying) { t in
            let point = Self.arc(from: from, to: to, t: t)
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(1 - (vanishes ? 0.45 : 0.25) * t)
                .opacity(vanishes && t > 0.85 ? max(0, 1 - (t - 0.85) / 0.15) : 1)
                .offset(x: point.x - from.x, y: point.y - from.y)
        } keyframes: { _ in
            if flying {
                CubicKeyframe(1.0, duration: duration)
            } else {
                LinearKeyframe(0.0, duration: 0.01)
            }
        }
        .position(from)
    }

    /// Quadratic curve that lifts above both ends before dipping into the vessel.
    static func arc(from a: CGPoint, to b: CGPoint, t: Double) -> CGPoint {
        let lift = max(28, abs(b.x - a.x) * 0.35 + 18)
        let control = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - lift)
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x,
                       y: u * u * a.y + 2 * u * t * control.y + t * t * b.y)
    }
}

/// One clean ring where an ingredient lands: watery for pots and bowls, warm for pans and ovens,
/// pale for boards and plates.
struct Ripple: Identifiable, Equatable {
    enum Kind { case splash, sizzle, dust }
    let id = UUID()
    let kind: Kind

    static func kind(for asset: String?, in vessel: Vessel) -> Kind {
        if let asset, ["salt", "herb", "sheaf_of_rice", "jar", "canned_food"].contains(asset) { return .dust }
        switch vessel {
        case .pan, .oven: return .sizzle
        case .pot, .bowl: return .splash
        case .board, .plate: return .dust
        }
    }
}

struct RippleView: View {
    let kind: Ripple.Kind
    let width: CGFloat
    @State private var t: CGFloat = 0

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(color, lineWidth: 2.5)
                .frame(width: width, height: width * 0.42)
                .scaleEffect(0.35 + 0.95 * t)
                .opacity(Double(1 - t) * 0.8)
            Ellipse()
                .fill(color.opacity(0.35))
                .frame(width: width * 0.6, height: width * 0.25)
                .scaleEffect(0.4 + 0.5 * t)
                .opacity(Double(1 - t) * 0.6)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.55)) { t = 1 } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch kind {
        case .splash: Color(red: 0.55, green: 0.78, blue: 0.95)
        case .sizzle: Color(red: 0.98, green: 0.70, blue: 0.32)
        case .dust:   Color(white: 0.98)
        }
    }
}

/// Ingredients slide: an adaptive grid of bowls, one per ingredient, tap to tick off.
struct IngredientBowlGrid: View {
    let ingredients: [String]
    let checked: Set<Int>
    let toggle: (Int) -> Void

    var body: some View {
        let assets = ingredients.map(KitchenAssets.asset(for:))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 124), spacing: KitchenStyle.gridSpacing)],
                  spacing: KitchenStyle.gridSpacing) {
            ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                let isChecked = checked.contains(index)
                Button { toggle(index) } label: {
                    VStack(spacing: 6) {
                        BowlView(asset: assets[index])
                            .overlay(alignment: .topTrailing) {
                                if isChecked {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, Theme.actionFill)
                                }
                            }
                        Text(ingredient)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .strikethrough(isChecked)
                            .foregroundStyle(isChecked ? .secondary : .primary)
                    }
                    .opacity(isChecked ? 0.6 : 1)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: isChecked)
                .accessibilityLabel(ingredient)
                .accessibilityValue(isChecked ? "checked" : "not checked")
                .accessibilityHint("Double tap to \(isChecked ? "uncheck" : "check")")
            }
        }
    }
}
