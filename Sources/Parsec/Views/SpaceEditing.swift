import AppKit
import SwiftUI

struct ThemePoint: Hashable {
    var x: Double
    var y: Double
}

enum ThemeColorSpace {
    private static let lightBrightness = 0.96
    private static let darkBrightness = 0.34
    private static let autoBrightness = 0.88

    static func color(at point: ThemePoint, theme: SpaceTheme) -> ThemeColor {
        let saturation = (1 - point.y) * saturationScale(theme.vibrancy)
        let nsColor = NSColor(hue: point.x, saturation: saturation, brightness: brightness(for: theme.appearance), alpha: 1)
        return ThemeColor(red: nsColor.redComponent, green: nsColor.greenComponent, blue: nsColor.blueComponent)
    }

    static func point(for color: ThemeColor, vibrancy: Double) -> ThemePoint {
        let nsColor = NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        let relativeSaturation = min(nsColor.saturationComponent / saturationScale(vibrancy), 1)
        return ThemePoint(x: nsColor.hueComponent, y: 1 - relativeSaturation)
    }

    static func recolor(_ theme: inout SpaceTheme, points: [ThemePoint]) {
        theme.colors = points.map { color(at: $0, theme: theme) }
    }

    private static func saturationScale(_ vibrancy: Double) -> Double {
        0.2 + 0.8 * vibrancy
    }

    private static func brightness(for appearance: SpaceAppearance) -> Double {
        switch appearance {
        case .light: lightBrightness
        case .dark: darkBrightness
        case .auto: autoBrightness
        }
    }
}

struct ArcThemeEditor: View {
    @Bindable var space: Space

    private var points: [ThemePoint] {
        space.theme.colors.map { ThemeColorSpace.point(for: $0, vibrancy: space.theme.vibrancy) }
    }

    private var workspaceSwatch: ThemeColor? {
        space.theme.colors.count == 1 ? space.theme.colors[0] : nil
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                ThemeColorField(space: space, points: points)
                AppearancePicker(appearance: Binding(get: { space.theme.appearance }, set: { setAppearance($0) }))
                    .padding(.top, 12)
                HStack(spacing: 28) {
                    StopButton(symbolName: "minus", isEnabled: points.count > 1) { removeStop() }
                    StopButton(symbolName: "plus", isEnabled: points.count < SpaceTheme.maxColors) { addStop() }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
            }
            .frame(height: 250)
            ThemeSection(title: "Color del workspace") {
                VStack(alignment: .leading, spacing: 10) {
                    ColorPalettePicker(selection: workspaceSwatch) { color in
                        guard let color else { return }
                        space.theme.colors = [color]
                    }
                    Button(action: applyPrism) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(LinearGradient(colors: SpaceTheme.prism.colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                                .frame(width: 22, height: 22)
                            Text("Prisma").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .clickable()
                    .help("Degradado Prisma")
                    .accessibilityLabel("Tema Prisma")
                }
            }
            HStack(spacing: 18) {
                WavySlider(value: Binding(get: { space.theme.vibrancy }, set: { setVibrancy($0) }))
                    .frame(height: 44)
                    .help("Intensidad del color")
                GrainKnob(value: $space.theme.grain)
                    .help("Grain")
            }
            HStack(spacing: 8) {
                Image(systemName: "drop.halffull").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $space.theme.transparency, in: 0...0.9).controlSize(.small)
            }
            .help("Transparencia")
        }
        .padding(14)
        .frame(width: 360)
        .onDisappear { BrowserStore.shared.saveSoon() }
    }

    private func setAppearance(_ appearance: SpaceAppearance) {
        let currentPoints = points
        space.theme.appearance = appearance
        ThemeColorSpace.recolor(&space.theme, points: currentPoints)
    }

    private func applyPrism() {
        space.theme = .prism
    }

    private func setVibrancy(_ vibrancy: Double) {
        let currentPoints = points
        space.theme.vibrancy = vibrancy
        ThemeColorSpace.recolor(&space.theme, points: currentPoints)
    }

    private func addStop() {
        let lastPoint = points.last ?? ThemePoint(x: 0.5, y: 0.5)
        let newPoint = ThemePoint(x: (lastPoint.x + 0.18).truncatingRemainder(dividingBy: 1), y: lastPoint.y)
        ThemeColorSpace.recolor(&space.theme, points: points + [newPoint])
    }

    private func removeStop() {
        ThemeColorSpace.recolor(&space.theme, points: Array(points.dropLast()))
    }

}

struct ThemeColorField: View {
    private static let dotSpacing: CGFloat = 9
    private static let handleSize: CGFloat = 38

    @Bindable var space: Space
    let points: [ThemePoint]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                SpaceBackgroundView(theme: space.theme)
                    .blur(radius: 24)
                    .opacity(0.55)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Canvas { context, size in
                    var dotY = Self.dotSpacing / 2
                    while dotY < size.height {
                        var dotX = Self.dotSpacing / 2
                        while dotX < size.width {
                            context.fill(Path(ellipseIn: CGRect(x: dotX, y: dotY, width: 1.4, height: 1.4)), with: .color(.primary.opacity(0.18)))
                            dotX += Self.dotSpacing
                        }
                        dotY += Self.dotSpacing
                    }
                }
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(space.theme.colors.indices.contains(index) ? space.theme.colors[index].color : .gray)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 5))
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .frame(width: Self.handleSize, height: Self.handleSize)
                        .position(position(for: point, in: geometry.size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in move(index: index, to: value.location, in: geometry.size) }
                        )
                        .accessibilityLabel("Color \(index + 1)")
                }
            }
        }
    }

    private func position(for point: ThemePoint, in size: CGSize) -> CGPoint {
        let inset = Self.handleSize / 2
        return CGPoint(x: inset + point.x * (size.width - inset * 2), y: inset + point.y * (size.height - inset * 2))
    }

    private func move(index: Int, to location: CGPoint, in size: CGSize) {
        var updatedPoints = points
        guard updatedPoints.indices.contains(index) else { return }
        let inset = Self.handleSize / 2
        let relativeX = (location.x - inset) / max(size.width - inset * 2, 1)
        let relativeY = (location.y - inset) / max(size.height - inset * 2, 1)
        updatedPoints[index] = ThemePoint(x: min(max(relativeX, 0), 0.999), y: min(max(relativeY, 0), 1))
        ThemeColorSpace.recolor(&space.theme, points: updatedPoints)
    }
}

struct AppearancePicker: View {
    @Binding var appearance: SpaceAppearance

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SpaceAppearance.allCases, id: \.self) { option in
                Button { appearance = option } label: {
                    Image(systemName: symbol(for: option))
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(appearance == option ? 0.12 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: option))
            }
        }
    }

    private func symbol(for option: SpaceAppearance) -> String {
        switch option {
        case .auto: "sparkles"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    private func label(for option: SpaceAppearance) -> String {
        switch option {
        case .auto: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }
}

struct StopButton: View {
    let symbolName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName).font(.system(size: 15, weight: .medium)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(symbolName == "plus" ? "Agregar color" : "Quitar color")
    }
}

struct WavySlider: View {
    private static let amplitude: CGFloat = 7
    private static let wavelength: CGFloat = 30
    private static let thumbSize = CGSize(width: 20, height: 44)

    @Binding var value: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbX = CGFloat(value) * (width - Self.thumbSize.width) + Self.thumbSize.width / 2
            ZStack(alignment: .leading) {
                wave(width: width, height: geometry.size.height)
                    .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                wave(width: width, height: geometry.size.height)
                    .trim(from: 0, to: value)
                    .stroke(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in value = min(max(Double(gesture.location.x / width), 0), 1) }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Intensidad")
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            value = min(max(value + (direction == .increment ? 0.05 : -0.05), 0), 1)
        }
    }

    private func wave(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let midY = height / 2
            path.move(to: CGPoint(x: 2, y: midY))
            var x: CGFloat = 2
            while x <= width - 2 {
                path.addLine(to: CGPoint(x: x, y: midY + sin(x / Self.wavelength * .pi * 2) * Self.amplitude))
                x += 1
            }
        }
    }
}

struct GrainKnob: View {
    private static let tickCount = 22
    private static let size: CGFloat = 60
    private static let dragRange: CGFloat = 160

    @Binding var value: Double
    @ViewState private var valueAtDragStart: Double?

    var body: some View {
        ZStack {
            ForEach(0..<Self.tickCount, id: \.self) { tick in
                let fraction = Double(tick) / Double(Self.tickCount - 1)
                Circle()
                    .fill(Color.primary.opacity(fraction <= value ? 0.6 : 0.15))
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: -Self.size / 2)
                    .rotationEffect(.degrees(-135 + fraction * 270))
            }
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Image(nsImage: GrainTexture.image).resizable(resizingMode: .tile).opacity(value * 0.5).clipShape(Circle()))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .frame(width: Self.size - 18, height: Self.size - 18)
            Capsule()
                .fill(Color.white)
                .frame(width: 4, height: 10)
                .offset(y: -Self.size / 2 + 14)
                .rotationEffect(.degrees(-135 + value * 270))
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let startValue = valueAtDragStart ?? value
                    valueAtDragStart = startValue
                    let delta = Double((gesture.translation.width - gesture.translation.height) / Self.dragRange)
                    value = min(max(startValue + delta, 0), 1)
                }
                .onEnded { _ in valueAtDragStart = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Grain")
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            value = min(max(value + (direction == .increment ? 0.05 : -0.05), 0), 1)
        }
    }
}

@MainActor
enum SpaceMenu {
    static func entries(model: WindowModel, space: Space) -> [MenuEntry] {
        let store = BrowserStore.shared
        return [
            .action("Cambiar icono…", symbol: "face.smiling") {
                model.switchToSpace(space)
                model.spaceIconEditingID = space.id
            },
            .action("Renombrar…", symbol: "pencil") {
                guard let title = TextPrompt.ask(title: "Renombrar Space", initialValue: space.title) else { return }
                space.title = title
                store.saveSoon()
            },
            .action("Editar colores…", symbol: "paintpalette") {
                model.switchToSpace(space)
                model.isThemeEditorPresented = true
            },
            .submenu("Perfil", symbol: "person.crop.circle", entries: store.profiles.map { profile in
                .action(profile.name, symbol: profile.iconSymbol ?? "person", isSelected: profile.id == space.profileID) {
                    SpaceProfiles.assign(profile.id, to: space)
                }
            }),
            .divider,
            .action("Nueva carpeta", symbol: "folder.badge.plus") { store.insert(.folder(title: "Nueva carpeta"), into: .pinned(spaceID: space.id), at: 0) },
            .action("Compartir Space…", symbol: "square.and.arrow.up") { SharingPresenter.share(SpaceSharing.text(for: space), from: model.window) },
            .action("Administrar Spaces…", symbol: "gearshape") { AppDelegate.shared.openSettings(section: .spaces) },
            .divider,
            .action("Eliminar Space", symbol: "trash", isEnabled: model.spaces.count > 1, isDestructive: true) { SpaceDeletion.confirm(space, model: model) },
        ]
    }
}

@MainActor
enum SpaceProfiles {
    static func assign(_ profileID: UUID, to space: Space) {
        guard space.profileID != profileID else { return }
        space.allNodes.forEach(BrowserStore.shared.unloadPages)
        space.profileID = profileID
        BrowserStore.shared.saveSoon()
    }
}

@MainActor
enum SpaceSharing {
    static func text(for space: Space) -> String {
        let lines = space.allNodes.allTabs.compactMap { tab in tab.url.map { "\(tab.displayTitle) — \($0.absoluteString)" } }
        return ([space.title] + lines).joined(separator: "\n")
    }
}

@MainActor
enum SharingPresenter {
    static func share(_ text: String, from window: NSWindow?) {
        guard let contentView = window?.contentView else { return Clipboard.copy(text) }
        let mouseLocation = window?.mouseLocationOutsideOfEventStream ?? .zero
        let anchor = NSRect(origin: contentView.convert(mouseLocation, from: nil), size: CGSize(width: 1, height: 1))
        NSSharingServicePicker(items: [text]).show(relativeTo: anchor, of: contentView, preferredEdge: .maxY)
    }
}

@MainActor
enum TextPrompt {
    private static let fieldSize = CGSize(width: 260, height: 24)

    static func ask(title: String, initialValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: NSRect(origin: .zero, size: fieldSize))
        field.stringValue = initialValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
