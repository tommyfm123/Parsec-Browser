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
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.88)
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

    private var gradientColors: [Color] {
        let colors = theme.colors.map(\.color)
        return colors.count == 1 ? colors + colors : colors
    }

    var body: some View {
        ZStack {
            if !isGlass { VisualEffectBackground() }
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity((1 - theme.transparency) * (isGlass ? Self.glassGradientOpacity : 1))
            Image(nsImage: GrainTexture.image)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(theme.grain * Self.grainOpacityScale)
                .allowsHitTesting(false)
        }
    }
}

struct FaviconView: View {
    let url: URL?
    var size: CGFloat = 16
    var isDimmed = false

    var body: some View {
        Group {
            if let icon = FaviconStore.shared.icon(for: url) {
                Image(nsImage: icon).resizable().interpolation(.high)
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
    let page: WebPage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * (page?.progress ?? 0), height: LayoutConstants.loadingLineHeight)
                .opacity(page?.isLoading == true ? 1 : 0)
                .animation(Motion.snappy(reduceMotion: reduceMotion), value: page?.progress)
                .animation(.easeOut(duration: 0.3), value: page?.isLoading)
        }
        .frame(height: LayoutConstants.loadingLineHeight)
        .allowsHitTesting(false)
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

extension View {
    func clickable() -> some View {
        pointerStyle(.link)
    }

    func hoverHighlight(cornerRadius: CGFloat = 7, isActive: Bool = false) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, isActive: isActive))
    }
}

struct IconButton: View {
    let symbolName: String
    let label: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .hoverHighlight(cornerRadius: 7)
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

extension View {
    func themedForeground(_ theme: SpaceTheme) -> some View {
        modifier(ThemedForeground(theme: theme))
    }
}
