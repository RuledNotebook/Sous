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

/// Step slide scene: warm background, the vessel in the middle, the step's ingredients in bowls on an arc
/// above it, dropping in one after another when the slide becomes current.
struct StepSceneView: View {
    let step: RecipeStep
    var isActive = true
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let unit = min(w, h)
            let vesselSize = unit * 0.42
            let bowl = min(max(unit * 0.17, 44), 76)
            let items = Array(step.sceneItems.prefix(6))
            let center = CGPoint(x: w / 2, y: h * 0.52)
            ZStack {
                LinearGradient(colors: [KitchenStyle.warmTop, KitchenStyle.warmBottom], startPoint: .top, endPoint: .bottom)
                VesselView(vessel: step.sceneVessel, size: vesselSize)
                    .position(center)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(duration: 0.5, bounce: 0.2), value: appeared)
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    BowlView(asset: item.asset, label: item.asset == nil ? item.label : nil, width: bowl)
                        .position(Self.position(index: index, count: items.count, center: center,
                                                radiusX: min(w * 0.38, vesselSize * 0.7 + bowl * 0.9),
                                                radiusY: min(h * 0.3, vesselSize * 0.75)))
                        .offset(y: appeared ? 0 : -28)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(duration: 0.55, bounce: 0.25).delay(0.1 + Double(index) * 0.08), value: appeared)
                }
            }
        }
        .clipped()
        .onChange(of: isActive, initial: true) { _, active in appeared = active }
    }

    /// Bowls sit on a gentle arc over the top of the vessel, spread evenly from left to right.
    static func position(index: Int, count: Int, center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> CGPoint {
        let start = 200.0, end = 340.0        // degrees in screen coordinates: the upper arc
        let t = count <= 1 ? 0.5 : Double(index) / Double(count - 1)
        let angle = (start + (end - start) * t) * .pi / 180
        return CGPoint(x: center.x + radiusX * cos(angle), y: center.y + radiusY * sin(angle))
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
