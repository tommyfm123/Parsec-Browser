import AppKit
import SwiftUI

enum DownloadFlightMetrics {
    static let iconSize: CGFloat = 48
    static let appearDuration = 0.14
    static let travelDuration = 0.62
    static let fadeDuration = 0.12
    static let arrivalScale = 0.32
    static let launchScale = 1.08
    static let launchHeightFraction: CGFloat = 0.42
    static let launchWidthFraction: CGFloat = 0.62
    static let arrivalBounceScale = 1.22
    static let ringWidth: CGFloat = 2
    static let minimumRingProgress = 0.03
}

struct DownloadsButtonAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

struct DownloadsButton: View {
    @Bindable var model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var isPopoverPresented = false

    private var manager: DownloadManager { DownloadManager.shared }
    private var isDownloading: Bool { manager.activeCount > 0 }

    var body: some View {
        SidebarCircleButton(symbolName: isDownloading ? "arrow.down" : "arrow.down.to.line", label: "Descargas", action: togglePopover)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
                DownloadsPopover(onShowAll: openLibrary).matchingPopoverAppearance()
            }
            .overlay { DownloadProgressRing(progress: manager.activeProgress).opacity(isDownloading ? 1 : 0) }
            .keyframeAnimator(initialValue: 1.0, trigger: manager.startedItem?.id) { button, scale in
                button.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                LinearKeyframe(1, duration: DownloadFlightMetrics.appearDuration + DownloadFlightMetrics.travelDuration)
                SpringKeyframe(DownloadFlightMetrics.arrivalBounceScale, duration: 0.12)
                SpringKeyframe(1, duration: 0.32)
            }
            .anchorPreference(key: DownloadsButtonAnchorKey.self, value: .center) { $0 }
            .help(isDownloading ? "Descargando \(Int((manager.activeProgress * 100).rounded()))%" : "Descargas")
    }

    private func togglePopover() {
        isPopoverPresented.toggle()
    }

    private func openLibrary() {
        isPopoverPresented = false
        AppDelegate.shared.openDownloadsLibrary(profileID: model.profileID, allowsHistory: !model.isPrivate)
    }
}

struct DownloadProgressRing: View {
    let progress: Double

    var body: some View {
        Circle()
            .trim(from: 0, to: max(progress, DownloadFlightMetrics.minimumRingProgress))
            .stroke(Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: DownloadFlightMetrics.ringWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(DownloadFlightMetrics.ringWidth / 2)
            .animation(.easeOut(duration: 0.2), value: progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct DownloadFlightPath: ViewModifier, Animatable {
    var progress: Double
    let launchPoint: CGPoint
    let target: CGPoint

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.position(point)
    }

    private var point: CGPoint {
        let controlPoint = CGPoint(x: target.x, y: launchPoint.y)
        let remaining = 1 - progress
        let horizontal = remaining * remaining * launchPoint.x + 2 * remaining * progress * controlPoint.x + progress * progress * target.x
        let vertical = remaining * remaining * launchPoint.y + 2 * remaining * progress * controlPoint.y + progress * progress * target.y
        return CGPoint(x: horizontal, y: vertical)
    }
}

struct DownloadFlightOverlay: View {
    let target: CGPoint
    let containerSize: CGSize
    let isActiveWindow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var progress = 0.0
    @ViewState private var scale = DownloadFlightMetrics.launchScale
    @ViewState private var isVisible = false

    private var startedItem: DownloadItem? { DownloadManager.shared.startedItem }

    private var launchPoint: CGPoint {
        CGPoint(x: containerSize.width * DownloadFlightMetrics.launchWidthFraction, y: containerSize.height * DownloadFlightMetrics.launchHeightFraction)
    }

    private var fileIcon: NSImage {
        startedItem?.fileIcon ?? NSWorkspace.shared.icon(for: .data)
    }

    var body: some View {
        Image(nsImage: fileIcon)
            .resizable()
            .interpolation(.high)
            .frame(width: DownloadFlightMetrics.iconSize, height: DownloadFlightMetrics.iconSize)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .scaleEffect(scale)
            .opacity(isVisible ? 1 : 0)
            .modifier(DownloadFlightPath(progress: progress, launchPoint: launchPoint, target: target))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: startedItem?.id) { launch() }
    }

    private func launch() {
        guard isActiveWindow, !reduceMotion else { return }
        withAnimation(.easeOut(duration: DownloadFlightMetrics.appearDuration)) { isVisible = true }
        withAnimation(.easeIn(duration: DownloadFlightMetrics.travelDuration).delay(DownloadFlightMetrics.appearDuration)) {
            progress = 1
            scale = DownloadFlightMetrics.arrivalScale
        } completion: {
            withAnimation(.easeOut(duration: DownloadFlightMetrics.fadeDuration)) { isVisible = false } completion: { resetFlight() }
        }
    }

    private func resetFlight() {
        progress = 0
        scale = DownloadFlightMetrics.launchScale
    }
}

extension View {
    func downloadFlight(isActiveWindow: Bool) -> some View {
        overlayPreferenceValue(DownloadsButtonAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    DownloadFlightOverlay(target: proxy[anchor], containerSize: proxy.size, isActiveWindow: isActiveWindow)
                }
            }
        }
    }
}
