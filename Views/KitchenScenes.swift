import SwiftUI

// Scenes drawn from the bundled Kitchen art (Microsoft Fluent Emoji, MIT). No image generation.

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

/// Step slide scene: warm background, the vessel in the middle (a generated picture of the pot of water
/// or the empty pan when `SceneArtStore` has one, else the bundled art), the step's ingredients in bowls on
/// an arc above it. When the slide becomes current the ingredients drop into the vessel one after another,
/// each landing in a little puff; tap a bowl to drop that one, tap the vessel to see it all again.
struct StepSceneView: View {
    let step: RecipeStep
    var isActive = true
    @State private var appeared = false
    @State private var dropped: Set<Int> = []
    @State private var puffs: [Puff] = []
    @State private var sequence: Task<Void, Never>?
    private let art = SceneArtStore.shared

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let unit = min(w, h)
            let vesselSize = unit * 0.42
            let bowl = min(max(unit * 0.17, 44), 76)
            let items = Array(step.sceneItems.prefix(6))
            let center = CGPoint(x: w / 2, y: h * 0.52)
            let landing = CGPoint(x: center.x, y: center.y - vesselSize * 0.12)
            let key = SceneArtKey(step: step)
            ZStack {
                LinearGradient(colors: [KitchenStyle.warmTop, KitchenStyle.warmBottom], startPoint: .top, endPoint: .bottom)

                Group {
                    if let picture = art.image(for: key) {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFit()
                            .frame(width: vesselSize * 1.25, height: vesselSize * 1.25)
                            .shadow(color: KitchenStyle.shadow, radius: vesselSize * 0.06, y: vesselSize * 0.05)
                            .transition(.opacity)
                    } else {
                        VesselView(vessel: step.sceneVessel, size: vesselSize)
                    }
                }
                .position(center)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(duration: 0.5, bounce: 0.2), value: appeared)
                .animation(.easeInOut(duration: 0.35), value: art.images.count)
                .contentShape(Circle().scale(0.8))
                .onTapGesture { replay(items.count) }
                .accessibilityHidden(true)

                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let home = Self.position(index: index, count: items.count, center: center,
                                             radiusX: min(w * 0.38, vesselSize * 0.7 + bowl * 0.9),
                                             radiusY: min(h * 0.3, vesselSize * 0.75))
                    let isIn = dropped.contains(index)
                    // The bowl stays on the arc (empty once its ingredient has gone in).
                    BowlView(asset: nil, label: item.asset == nil ? item.label : nil, width: bowl)
                        .position(home)
                        .offset(y: appeared ? 0 : -28)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(duration: 0.55, bounce: 0.25).delay(0.1 + Double(index) * 0.08), value: appeared)
                        .onTapGesture { drop(index, of: items.count) }
                    // The ingredient itself: in its bowl, then flying into the vessel.
                    if let asset = item.asset {
                        Image(asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: bowl * 0.6, height: bowl * 0.6)
                            .position(isIn ? landing : CGPoint(x: home.x, y: home.y - bowl * 0.14))
                            .scaleEffect(isIn ? 0.25 : 1)
                            .opacity(isIn ? 0 : (appeared ? 1 : 0))
                            .animation(isIn ? .easeIn(duration: 0.55) : .spring(duration: 0.55, bounce: 0.25).delay(0.1 + Double(index) * 0.08),
                                       value: isIn)
                            .animation(.spring(duration: 0.55, bounce: 0.25).delay(0.1 + Double(index) * 0.08), value: appeared)
                            .allowsHitTesting(false)
                    }
                }

                ForEach(puffs) { puff in
                    PuffView(puff: puff).position(landing)
                }
            }
        }
        .clipped()
        .onChange(of: isActive, initial: true) { _, active in
            appeared = active
            if active { replay(step.sceneItems.prefix(6).count) } else { sequence?.cancel(); dropped = []; puffs = [] }
        }
        .onDisappear { sequence?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sceneLabel)
        .accessibilityAction(named: "Show the ingredients go in") { replay(step.sceneItems.prefix(6).count) }
    }

    private var sceneLabel: String {
        let names = step.sceneItems.prefix(6).map(\.label)
        return names.isEmpty ? "\(step.sceneVessel.rawValue)" : "\(names.joined(separator: ", ")) into the \(step.sceneVessel.rawValue)"
    }

    /// Everything back in its bowl, then in they go, one at a time.
    private func replay(_ count: Int) {
        sequence?.cancel()
        dropped = []
        puffs = []
        guard count > 0 else { return }
        sequence = Task {
            try? await Task.sleep(for: .milliseconds(900))
            for index in 0..<count {
                guard !Task.isCancelled else { return }
                drop(index, of: count)
                try? await Task.sleep(for: .milliseconds(520))
            }
        }
    }

    private func drop(_ index: Int, of count: Int) {
        guard !dropped.contains(index) else { return }
        withAnimation { _ = dropped.insert(index) }
        let items = Array(step.sceneItems.prefix(6))
        let kind = Puff.kind(for: items.indices.contains(index) ? items[index].asset : nil, in: step.sceneVessel)
        let puff = Puff(kind: kind)
        Task {
            try? await Task.sleep(for: .milliseconds(420))   // when the ingredient reaches the rim
            puffs.append(puff)
            try? await Task.sleep(for: .milliseconds(900))
            puffs.removeAll { $0.id == puff.id }
        }
    }

    /// Bowls sit on a gentle arc over the top of the vessel, spread evenly from left to right.
    static func position(index: Int, count: Int, center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> CGPoint {
        let start = 200.0, end = 340.0        // degrees in screen coordinates: the upper arc
        let t = count <= 1 ? 0.5 : Double(index) / Double(count - 1)
        let angle = (start + (end - start) * t) * .pi / 180
        return CGPoint(x: center.x + radiusX * cos(angle), y: center.y + radiusY * sin(angle))
    }
}

/// A little burst where an ingredient lands: a splash for liquids, a sizzle over a pan, a dusting for powders.
struct Puff: Identifiable, Equatable {
    enum Kind { case splash, sizzle, powder }
    let id = UUID()
    let kind: Kind

    static func kind(for asset: String?, in vessel: Vessel) -> Kind {
        if let asset, ["salt", "honey_pot", "herb", "sheaf_of_rice", "jar", "canned_food"].contains(asset) { return .powder }
        switch vessel {
        case .pan, .oven: return .sizzle
        case .pot, .bowl: return .splash
        case .board, .plate: return .powder
        }
    }
}

struct PuffView: View {
    let puff: Puff
    @State private var t: CGFloat = 0
    private let count = 9

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi + Double(puff.id.hashValue % 7) * 0.13
                let distance: CGFloat = puff.kind == .powder ? 22 : 34
                Circle()
                    .fill(color)
                    .frame(width: size(i), height: size(i))
                    .offset(x: cos(angle) * distance * t, y: sin(angle) * distance * t * 0.6 - (puff.kind == .sizzle ? 18 * t : 6 * t))
                    .opacity(Double(1 - t))
                    .scaleEffect(1 + t * 0.6)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { t = 1 } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func size(_ i: Int) -> CGFloat { CGFloat(4 + (i % 3) * 2) }

    private var color: Color {
        switch puff.kind {
        case .splash: Color(red: 0.62, green: 0.82, blue: 0.95)
        case .sizzle: Color(red: 0.98, green: 0.72, blue: 0.35)
        case .powder: Color(white: 0.97)
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
                                        .foregroundStyle(.white, Theme.basil)
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
