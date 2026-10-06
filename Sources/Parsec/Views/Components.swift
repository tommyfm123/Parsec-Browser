import AppKit
import SwiftUI
import WebKit

typealias ViewState<Value> = SwiftUICore.State<Value>

enum Radius {
    static let window: CGFloat = 14
    static let card: CGFloat = 12
    static let control: CGFloat = 9
    static let row: CGFloat = 8
}

enum Motion {
    static func spring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)
    }

    static func snappy(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.9)
    }

    static func disclosure(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.2, dampingFraction: 0.92)
    }
}

struct WebViewHost: NSViewRepresentable {
    private static let latestContainers = NSMapTable<WKWebView, NSView>.weakToWeakObjects()

    private static let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    private static let bottomCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

    let webView: WKWebView
    var cornerRadius: CGFloat = 0
    var roundsTopCorners = true

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        applyCorners(to: container)
        Self.latestContainers.setObject(container, forKey: webView)
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        applyCorners(to: container)
        let isLatestContainer = Self.latestContainers.object(forKey: webView) === container
        guard isLatestContainer, webView.superview !== container else { return }
        attach(to: container)
    }

    private func applyCorners(to container: NSView) {
        container.layer?.cornerRadius = cornerRadius
        container.layer?.maskedCorners = roundsTopCorners ? Self.allCorners : Self.bottomCorners
    }

    private func attach(to container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct OpaqueWindowBackground: View {
    private static let windowColorOpacity = 0.88

    var body: some View {
        VisualEffectBackground(material: .hudWindow)
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(Self.windowColorOpacity))
    }
}

final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else { return window?.performZoom(nil) ?? () }
        window?.performDrag(with: event)
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView { WindowDragNSView() }
    func updateNSView(_ view: WindowDragNSView, context: Context) {}
}

@MainActor
enum GrainTexture {
    private static let side = 160

    static let image: NSImage = {
        var generator = SystemRandomNumberGenerator()
        let pixelCount = side * side
        var pixels = [UInt8](repeating: 0, count: pixelCount)
        for index in 0..<pixelCount {
            pixels[index] = UInt8.random(in: 0...255, using: &generator)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return NSImage(cgImage: cgImage, size: NSSize(width: side / 2, height: side / 2))
    }()
}

struct SpaceBackgroundView: View {
    private static let grainOpacityScale = 0.28
    private static let glassGradientOpacity = 0.55
    let theme: SpaceTheme
    var isGlass = false
    var usesMesh = false

    private var gradientColors: [Color] {
        let colors = theme.colors.map(\.color)
        return colors.count == 1 ? colors + colors : colors
    }

    var body: some View {
        ZStack {
            if !isGlass { VisualEffectBackground() }
            Group {
                if usesMesh, theme.colors.count == SpaceTheme.maxColors {
                    MeshGradient(width: 3, height: 3, points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5, 0.5], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1],
                    ], colors: [
                        gradientColors[0], gradientColors[0], gradientColors[1],
                        gradientColors[0], gradientColors[1], gradientColors[2],
                        gradientColors[1], gradientColors[1], gradientColors[2],
                    ])
                } else {
                    LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
                .opacity((1 - theme.transparency) * (isGlass ? Self.glassGradientOpacity : 1))
            Image(nsImage: GrainTexture.image)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(theme.grain * Self.grainOpacityScale)
                .allowsHitTesting(false)
        }
    }
}

private struct FaviconNetworkKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var allowsFaviconNetwork: Bool {
        get { self[FaviconNetworkKey.self] }
        set { self[FaviconNetworkKey.self] = newValue }
    }
}

@MainActor
enum FaviconTone {
    private static let sampleSide = 16
    private static let grayscaleSaturationLimit = 0.1
    private static let glyphCoverageLimit = 0.7
    private static let darkLuminanceLimit = 0.3
    private static let lightLuminanceLimit = 0.82
    private static let unmeasurable = -1.0
    private static let accentSaturationFloor = 0.3
    private static let accentOpacityFloor = 0.5
    private static let accentMinimumWeight = 3.0
    private static let hueBucketCount = 12
    private static let cache = NSMapTable<NSImage, NSNumber>.weakToStrongObjects()
    private static let accentCache = NSMapTable<NSImage, NSColor>.weakToStrongObjects()

    private struct SampledPixel {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        var saturation: Double { max(red, green, blue) - min(red, green, blue) }
        var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
        var hue: Double { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).hueComponent }
    }

    static func needsInversion(_ image: NSImage, colorScheme: ColorScheme) -> Bool {
        let luminance = glyphLuminance(of: image)
        guard luminance != unmeasurable else { return false }
        return colorScheme == .dark ? luminance < darkLuminanceLimit : luminance > lightLuminanceLimit
    }

    static func accentColor(of image: NSImage) -> Color? {
        let accent = accentCache.object(forKey: image) ?? measureAccent(image)
        accentCache.setObject(accent, forKey: image)
        return accent.alphaComponent > 0 ? Color(nsColor: accent) : nil
    }

    private static func glyphLuminance(of image: NSImage) -> Double {
        if let cached = cache.object(forKey: image) { return cached.doubleValue }
        let luminance = measureGlyphLuminance(image)
        cache.setObject(NSNumber(value: luminance), forKey: image)
        return luminance
    }

    private static func sampledPixels(of image: NSImage) -> [SampledPixel]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var bytes = [UInt8](repeating: 0, count: sampleSide * sampleSide * 4)
        let isDrawn = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: sampleSide, height: sampleSide, bitsPerComponent: 8, bytesPerRow: sampleSide * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
            return true
        }
        guard isDrawn else { return nil }
        return stride(from: 0, to: bytes.count, by: 4).map { offset in
            SampledPixel(red: Double(bytes[offset]) / 255, green: Double(bytes[offset + 1]) / 255, blue: Double(bytes[offset + 2]) / 255, alpha: Double(bytes[offset + 3]) / 255)
        }
    }

    private static func measureGlyphLuminance(_ image: NSImage) -> Double {
        guard let pixels = sampledPixels(of: image) else { return unmeasurable }
        let coverage = pixels.reduce(0) { $0 + $1.alpha }
        let saturation = pixels.reduce(0) { $0 + $1.saturation }
        let luminance = pixels.reduce(0) { $0 + $1.luminance }
        let isGlyph = coverage > 0 && coverage / Double(pixels.count) < glyphCoverageLimit && saturation / coverage < grayscaleSaturationLimit
        return isGlyph ? luminance / coverage : unmeasurable
    }

    private static func measureAccent(_ image: NSImage) -> NSColor {
        let vividPixels = (sampledPixels(of: image) ?? []).compactMap { pixel -> SampledPixel? in
            guard pixel.alpha >= accentOpacityFloor else { return nil }
            let opaque = SampledPixel(red: pixel.red / pixel.alpha, green: pixel.green / pixel.alpha, blue: pixel.blue / pixel.alpha, alpha: 1)
            return opaque.saturation >= accentSaturationFloor ? opaque : nil
        }
        let buckets = Dictionary(grouping: vividPixels) { min(Int($0.hue * Double(hueBucketCount)), hueBucketCount - 1) }
        let bucketWeights = buckets.mapValues { $0.reduce(0) { $0 + $1.saturation } }
        guard let heaviest = bucketWeights.max(by: { $0.value < $1.value }), heaviest.value >= accentMinimumWeight,
              let dominant = buckets[heaviest.key] else { return .clear }
        let count = Double(dominant.count)
        return NSColor(
            srgbRed: dominant.reduce(0) { $0 + $1.red } / count,
            green: dominant.reduce(0) { $0 + $1.green } / count,
            blue: dominant.reduce(0) { $0 + $1.blue } / count,
            alpha: 1
        )
    }
}

struct FaviconView: View {
    let url: URL?
    var size: CGFloat = 16
    var isDimmed = false
    var allowsNetwork = true
    @Environment(\.allowsFaviconNetwork) private var environmentAllowsNetwork
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let icon = FaviconStore.shared.icon(for: url, allowsNetwork: allowsNetwork && environmentAllowsNetwork) {
                let image = Image(nsImage: icon).resizable().interpolation(.high)
                if FaviconTone.needsInversion(icon, colorScheme: colorScheme) {
                    image.colorInvert()
                } else {
                    image
                }
            } else if url == nil, let mark = BrandMark.image {
                Image(nsImage: mark).resizable().renderingMode(.template).interpolation(.high).foregroundStyle(.primary)
            } else {
                Image(systemName: "globe").resizable().foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .opacity(isDimmed ? 0.5 : 1)
    }
}

struct LoadingLineView: View {
    private static let height: CGFloat = 2.5
    private static let horizontalInset: CGFloat = 16
    private static let topInset: CGFloat = 4
    private static let glowRadius: CGFloat = 4
    private static let minimumProgress = 0.08
    private static let shimmerPeriod = 1.1
    private static let shimmerWidth = 0.22
    private static let colors = [
        Color(red: 0.36, green: 0.62, blue: 1), Color(red: 0.6, green: 0.45, blue: 1), Color(red: 0.95, green: 0.47, blue: 0.76),
    ]

    let page: WebPage?
    @ViewState private var displayedProgress = 0.0
    @ViewState private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(paused: !isVisible || reduceMotion)) { context in
                bar(phase: reduceMotion ? 0 : shimmerPhase(at: context.date))
            }
            .frame(width: max(geometry.size.width - Self.horizontalInset * 2, 0) * displayedProgress, height: Self.height)
            .offset(x: Self.horizontalInset, y: Self.topInset)
        }
        .frame(height: Self.height + Self.topInset + Self.glowRadius)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: page?.progress, initial: true) { update() }
        .onChange(of: page?.isLoading) { update() }
    }

    private func bar(phase: Double) -> some View {
        let gradient = LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing)
        let shimmer = LinearGradient(
            colors: [.clear, .white.opacity(0.75), .clear],
            startPoint: UnitPoint(x: phase - Self.shimmerWidth, y: 0.5),
            endPoint: UnitPoint(x: phase + Self.shimmerWidth, y: 0.5)
        )
        return Capsule()
            .fill(gradient)
            .overlay(Capsule().fill(shimmer))
            .background(Capsule().fill(gradient).blur(radius: Self.glowRadius).opacity(0.7))
    }

    private func shimmerPhase(at date: Date) -> Double {
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.shimmerPeriod) / Self.shimmerPeriod
        return cycle * (1 + Self.shimmerWidth * 2) - Self.shimmerWidth
    }

    private func update() {
        guard let page else { return }
        guard !page.isLoading else { return show(progress: page.progress) }
        guard isVisible else { return }
        withAnimation(.smooth(duration: 0.25)) { displayedProgress = 1 }
        withAnimation(.easeOut(duration: 0.4).delay(0.25)) { isVisible = false }
    }

    private func show(progress: Double) {
        if !isVisible { displayedProgress = Self.minimumProgress }
        withAnimation(.easeOut(duration: 0.2)) { isVisible = true }
        withAnimation(.smooth(duration: 0.4)) { displayedProgress = max(progress, Self.minimumProgress, displayedProgress) }
    }
}

struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    var isActive = false
    @ViewState private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isActive ? 0.12 : isHovering ? 0.09 : 0))
            )
            .onHover { isHovering = $0 }
            .pointerStyle(.link)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

enum PointerClick {
    static var isDoubleClick: Bool { (NSApp.currentEvent?.clickCount ?? 1) > 1 }
}

extension View {
    func clickable() -> some View {
        pointerStyle(.link)
    }

    func hoverHighlight(cornerRadius: CGFloat = 7, isActive: Bool = false) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, isActive: isActive))
    }
}

struct SheetButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    private static let height: CGFloat = 34
    private static let pressedOpacity = 0.8
    private static let disabledOpacity = 0.35

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isPrimary = kind == .primary
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isPrimary ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.75))
            .padding(.horizontal, 20)
            .frame(height: Self.height)
            .background(Capsule().fill(isPrimary ? Color.primary : Color.clear))
            .hoverHighlight(cornerRadius: Self.height / 2)
            .opacity(isEnabled ? (configuration.isPressed ? Self.pressedOpacity : 1) : Self.disabledOpacity)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == SheetButtonStyle {
    static var sheetPrimary: SheetButtonStyle { SheetButtonStyle(kind: .primary) }
    static var sheetSecondary: SheetButtonStyle { SheetButtonStyle(kind: .secondary) }
}

@MainActor
enum LiquidGlass {
    private static let identityThreshold = 0.03
    private static let clearGlassThreshold = 0.7
    private static let maximumSolidOpacity = 0.92
    private static let borderOpacity = 0.12

    static var level: Double {
        min(max(BrowserStore.shared.settings.liquidGlass, 0), 1)
    }

    static var surfaceOpacity: Double {
        min(max(BrowserStore.shared.settings.surfaceOpacity, 0), 1)
    }

    static func material(level: Double, interactive: Bool, tint: Color?) -> Glass {
        guard level >= identityThreshold else { return .identity }
        let base: Glass = level >= clearGlassThreshold ? .clear : .regular
        let tinted = tint.map { base.tint($0) } ?? base
        return interactive ? tinted.interactive() : tinted
    }

    static func solidOpacity(level: Double) -> Double {
        (1 - level) * maximumSolidOpacity * surfaceOpacity
    }

    static func borderOpacity(level: Double) -> Double {
        borderOpacity * (1 - level * 0.5)
    }

    static func solidFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.26) : Color.white
    }

    static func activeFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.7)
    }
}

struct LiquidGlassModifier<GlassShape: InsettableShape>: ViewModifier {
    let shape: GlassShape
    var isActive = false
    var interactive = false
    var tint: Color? = nil
    var showsBorder = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let level = LiquidGlass.level
        content
            .background {
                ZStack {
                    shape.fill(LiquidGlass.solidFill(colorScheme)).opacity(LiquidGlass.solidOpacity(level: level))
                    shape.fill(LiquidGlass.activeFill(colorScheme)).opacity(isActive ? 1 : 0)
                    shape.strokeBorder(Color.primary.opacity(showsBorder ? LiquidGlass.borderOpacity(level: level) : 0), lineWidth: 0.75)
                }
                .animation(.easeOut(duration: 0.12), value: isActive)
            }
            .glassEffect(LiquidGlass.material(level: level, interactive: interactive, tint: tint), in: shape)
    }
}

extension View {
    func liquidGlass<GlassShape: InsettableShape>(in shape: GlassShape, isActive: Bool = false, interactive: Bool = false, tint: Color? = nil, showsBorder: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: shape, isActive: isActive, interactive: interactive, tint: tint, showsBorder: showsBorder))
    }

    func liquidGlassButton(prominent: Bool = false) -> some View {
        modifier(LiquidGlassButtonModifier(prominent: prominent))
    }
}

private struct LiquidGlassButtonModifier: ViewModifier {
    var prominent = false

    func body(content: Content) -> some View {
        let level = LiquidGlass.level
        if level < 0.08 {
            solidStyle(content)
        } else if prominent {
            content.buttonStyle(.glass(LiquidGlass.material(level: level, interactive: true, tint: Color.accentColor.opacity(0.3 + 0.35 * level))))
        } else {
            content.buttonStyle(.glass(LiquidGlass.material(level: level, interactive: true, tint: nil)))
        }
    }

    @ViewBuilder
    private func solidStyle(_ content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct IconButton: View {
    let symbolName: String
    let label: String
    var isEnabled = true
    let action: () -> Void
    @ViewState private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 8, style: .continuous), isActive: isHovering, interactive: true, showsBorder: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct ThemedForeground: ViewModifier {
    let theme: SpaceTheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, theme.isDark ? .dark : .light)
    }
}

struct PopoverAppearance: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.preferredColorScheme(colorScheme)
    }
}

extension View {
    func themedForeground(_ theme: SpaceTheme) -> some View {
        modifier(ThemedForeground(theme: theme))
    }

    func matchingPopoverAppearance() -> some View {
        modifier(PopoverAppearance())
    }
}

extension NSResponder {
    var isInsideWebView: Bool {
        guard let view = self as? NSView else { return false }
        return sequence(first: view, next: \.superview).contains { $0 is WKWebView }
    }
}
