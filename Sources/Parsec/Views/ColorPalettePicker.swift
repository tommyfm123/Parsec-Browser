import AppKit
import SwiftUI

struct Swatch: Identifiable, Hashable {
    let name: String
    let color: ThemeColor

    var id: String { name }
}

enum SwatchPalette {
    static let maximumCustomColors = 8
    static let minimumBrightness = 0.05

    static let presets: [Swatch] = [
        Swatch(name: "Azul", color: ThemeColor(red: 0, green: 0.48, blue: 1)),
        Swatch(name: "Índigo", color: ThemeColor(red: 0.32, green: 0.28, blue: 0.96)),
        Swatch(name: "Violeta", color: ThemeColor(red: 0.55, green: 0.36, blue: 0.96)),
        Swatch(name: "Rosa", color: ThemeColor(red: 0.93, green: 0.33, blue: 0.6)),
        Swatch(name: "Rojo", color: ThemeColor(red: 0.95, green: 0.32, blue: 0.3)),
        Swatch(name: "Naranja", color: ThemeColor(red: 0.98, green: 0.55, blue: 0.18)),
        Swatch(name: "Amarillo", color: ThemeColor(red: 0.98, green: 0.78, blue: 0.2)),
        Swatch(name: "Verde", color: ThemeColor(red: 0.2, green: 0.72, blue: 0.45)),
        Swatch(name: "Cian", color: ThemeColor(red: 0.16, green: 0.68, blue: 0.78)),
        Swatch(name: "Grafito", color: ThemeColor(red: 0.3, green: 0.3, blue: 0.33)),
        Swatch(name: "Niebla", color: ThemeColor(red: 0.84, green: 0.85, blue: 0.88)),
    ]

    static var defaultIcon: ThemeColor { presets[0].color }

    static func color(hue: Double, saturation: Double, brightness: Double) -> ThemeColor {
        let nsColor = NSColor(
            hue: min(max(hue, 0), 0.999),
            saturation: min(max(saturation, 0), 1),
            brightness: min(max(brightness, minimumBrightness), 1),
            alpha: 1
        )
        return ThemeColor(red: nsColor.redComponent, green: nsColor.greenComponent, blue: nsColor.blueComponent)
    }

    static func components(of color: ThemeColor) -> (hue: Double, saturation: Double, brightness: Double) {
        let nsColor = NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        return (nsColor.hueComponent, nsColor.saturationComponent, nsColor.brightnessComponent)
    }

    static func isPreset(_ color: ThemeColor) -> Bool {
        presets.contains { $0.color.matches(color) }
    }
}

@MainActor
enum PaletteMemory {
    static func remember(_ color: ThemeColor, replacing previous: ThemeColor?) {
        guard !SwatchPalette.isPreset(color) else { return }
        let store = BrowserStore.shared
        var colors = store.settings.customColors
        if let previous, !SwatchPalette.isPreset(previous) {
            colors.removeAll { $0.matches(previous) }
        }
        colors.removeAll { $0.matches(color) }
        colors.insert(color, at: 0)
        store.settings.customColors = Array(colors.prefix(SwatchPalette.maximumCustomColors))
        store.saveSoon()
    }

    static func remove(_ color: ThemeColor) {
        let store = BrowserStore.shared
        store.settings.customColors = store.settings.customColors.filter { !$0.matches(color) }
        store.saveSoon()
    }
}

struct ColorPalettePicker: View {
    private static let columns = [GridItem(.adaptive(minimum: 26, maximum: 26), spacing: 6)]

    var title: String? = nil
    let selection: ThemeColor?
    var automaticColors: [ThemeColor]? = nil
    let onSelect: (ThemeColor?) -> Void

    @ViewState private var showsPalette = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: BrowserStore { BrowserStore.shared }

    private var customColors: [ThemeColor] {
        store.settings.customColors.filter { !SwatchPalette.isPreset($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 6) {
                if let automaticColors, let first = automaticColors.first {
                    ColorSwatchButton(colors: automaticColors, isSelected: selection == nil, label: "Igual que el workspace", showsLink: true, linkLuminance: first.luminance) {
                        onSelect(nil)
                    }
                }
                ForEach(SwatchPalette.presets) { swatch in
                    ColorSwatchButton(colors: [swatch.color], isSelected: isSelected(swatch.color), label: swatch.name) {
                        onSelect(swatch.color)
                    }
                }
                PaletteToggleButton(isSelected: showsPalette) { showsPalette.toggle() }
            }
            if !customColors.isEmpty {
                Text("Tus colores").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 6) {
                    ForEach(customColors, id: \.self) { color in
                        ColorSwatchButton(colors: [color], isSelected: isSelected(color), label: "Color personalizado") {
                            onSelect(color)
                        }
                        .contextMenu {
                            Button("Quitar") { PaletteMemory.remove(color) }
                        }
                    }
                }
            }
            if showsPalette {
                PaletteCanvas(selection: selection, onChange: { onSelect($0) }, onCommit: { color, previous in
                    onSelect(color)
                    PaletteMemory.remember(color, replacing: previous)
                })
            }
        }
        .animation(reduceMotion ? .linear(duration: 0) : .easeOut(duration: 0.16), value: showsPalette)
    }

    private func isSelected(_ color: ThemeColor) -> Bool {
        guard let selection else { return false }
        return selection.matches(color)
    }
}

private struct ColorSwatchButton: View {
    let colors: [ThemeColor]
    let isSelected: Bool
    let label: String
    var showsLink = false
    var linkLuminance = 0.0
    let action: () -> Void

    private var gradientColors: [Color] {
        let fills = colors.map(\.color)
        return fills.count == 1 ? fills + fills : fills
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
                .overlay {
                    if showsLink {
                        Image(systemName: "link")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(linkLuminance > 0.62 ? Color.black.opacity(0.72) : Color.white)
                    }
                }
                .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0.18), lineWidth: isSelected ? 2 : 1))
                .padding(2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .clickable()
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PaletteToggleButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0.18), lineWidth: isSelected ? 2 : 1))
                .padding(2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .clickable()
        .help("Elegir un color en la paleta")
        .accessibilityLabel("Paleta de colores")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PaletteCanvas: View {
    private static let stripHeight: CGFloat = 18
    private static let squareHeight: CGFloat = 112
    private static let handleSize: CGFloat = 16
    private static let hueSteps = 48
    private static let squareSteps = 24

    let selection: ThemeColor?
    let onChange: (ThemeColor) -> Void
    let onCommit: (ThemeColor, ThemeColor?) -> Void

    @ViewState private var colorAtDragStart: ThemeColor?

    private var components: (hue: Double, saturation: Double, brightness: Double) {
        SwatchPalette.components(of: selection ?? SwatchPalette.defaultIcon)
    }

    var body: some View {
        VStack(spacing: 8) {
            hueStrip
            saturationSquare
        }
    }

    private var hueStrip: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    let cellWidth = size.width / CGFloat(Self.hueSteps)
                    for column in 0..<Self.hueSteps {
                        let hue = (Double(column) + 0.5) / Double(Self.hueSteps)
                        let rect = CGRect(x: CGFloat(column) * cellWidth, y: 0, width: cellWidth + 0.6, height: size.height)
                        context.fill(Path(rect), with: .color(SwatchPalette.color(hue: hue, saturation: 1, brightness: 1).color))
                    }
                }
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                if selection != nil {
                    PaletteHandle(color: SwatchPalette.color(hue: components.hue, saturation: 1, brightness: 1).color, diameter: 14)
                        .position(x: min(max(components.hue, 0), 1) * geometry.size.width, y: geometry.size.height / 2)
                }
            }
            .contentShape(Capsule())
            .gesture(drag(in: geometry.size, kind: .hue))
            .accessibilityElement()
            .accessibilityLabel("Tono")
            .accessibilityAdjustableAction { direction in
                nudgeHue(direction == .increment ? 0.04 : -0.04)
            }
        }
        .frame(height: Self.stripHeight)
    }

    private var saturationSquare: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let cellWidth = size.width / CGFloat(Self.squareSteps)
                    let cellHeight = size.height / CGFloat(Self.squareSteps)
                    for row in 0..<Self.squareSteps {
                        for column in 0..<Self.squareSteps {
                            let saturation = (Double(column) + 0.5) / Double(Self.squareSteps)
                            let brightness = 1 - (Double(row) + 0.5) / Double(Self.squareSteps)
                            let rect = CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth + 0.6, height: cellHeight + 0.6)
                            context.fill(Path(rect), with: .color(SwatchPalette.color(hue: components.hue, saturation: saturation, brightness: brightness).color))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                if let selection {
                    PaletteHandle(color: selection.color, diameter: Self.handleSize)
                        .position(x: components.saturation * geometry.size.width, y: (1 - components.brightness) * geometry.size.height)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .gesture(drag(in: geometry.size, kind: .square))
            .accessibilityElement()
            .accessibilityLabel("Paleta de colores")
            .accessibilityAdjustableAction { direction in
                nudgeSaturation(direction == .increment ? 0.08 : -0.08)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.squareHeight)
    }

    private enum DragKind {
        case hue
        case square
    }

    private func drag(in size: CGSize, kind: DragKind) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if colorAtDragStart == nil { colorAtDragStart = selection }
                onChange(color(at: value.location, in: size, kind: kind))
            }
            .onEnded { value in
                onCommit(color(at: value.location, in: size, kind: kind), colorAtDragStart)
                colorAtDragStart = nil
            }
    }

    private func color(at location: CGPoint, in size: CGSize, kind: DragKind) -> ThemeColor {
        switch kind {
        case .hue:
            let hue = min(max(location.x / max(size.width, 1), 0), 0.999)
            let saturation = components.saturation < 0.08 ? 0.85 : components.saturation
            let brightness = components.brightness < 0.08 ? 0.9 : components.brightness
            return SwatchPalette.color(hue: hue, saturation: saturation, brightness: brightness)
        case .square:
            let saturation = min(max(location.x / max(size.width, 1), 0), 1)
            let brightness = 1 - min(max(location.y / max(size.height, 1), 0), 1)
            return SwatchPalette.color(hue: components.hue, saturation: saturation, brightness: brightness)
        }
    }

    private func nudgeHue(_ delta: Double) {
        let wrapped = (components.hue + delta).truncatingRemainder(dividingBy: 1)
        let hue = wrapped < 0 ? wrapped + 1 : wrapped
        let color = SwatchPalette.color(hue: hue, saturation: max(components.saturation, 0.85), brightness: max(components.brightness, 0.55))
        onCommit(color, selection)
    }

    private func nudgeSaturation(_ delta: Double) {
        let color = SwatchPalette.color(hue: components.hue, saturation: min(max(components.saturation + delta, 0), 1), brightness: components.brightness)
        onCommit(color, selection)
    }
}

private struct PaletteHandle: View {
    let color: Color
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }
}
