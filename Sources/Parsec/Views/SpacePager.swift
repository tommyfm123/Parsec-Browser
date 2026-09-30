import AppKit
import SwiftUI

struct SpacePager: View {
    @Bindable var model: WindowModel
    @ViewState private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOnLastSpace: Bool { model.currentSpaceIndex == model.spaces.count - 1 }

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            HStack(spacing: 0) {
                ForEach(Array(model.spaces.enumerated()), id: \.element.id) { index, space in
                    Group {
                        if abs(index - model.currentSpaceIndex) <= 1 {
                            SpaceContentView(model: model, space: space)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: pageWidth)
                    .allowsHitTesting(index == model.currentSpaceIndex)
                }
            }
            .offset(x: -CGFloat(model.currentSpaceIndex) * pageWidth + dragOffset)
            .animation(Motion.spring(reduceMotion: reduceMotion), value: model.currentSpaceIndex)
            .frame(width: pageWidth, alignment: .leading)
            .background(SwipeMonitor(onChange: { trackSwipe($0, width: pageWidth) }, onEnd: { finishSwipe($0, width: pageWidth) }))
            .overlay(alignment: .center) {
                NewSpaceSwipeIndicator(progress: model.newSpacePullProgress)
            }
        }
        .clipped()
    }

    private func trackSwipe(_ offset: CGFloat, width: CGFloat) {
        dragOffset = rubberBand(offset, width: width)
        let isPullingPastEnd = isOnLastSpace && offset < 0 && !model.isPrivate
        model.newSpacePullProgress = isPullingPastEnd ? min(-offset / (width * LayoutConstants.newSpaceSwipeThreshold), 1) : 0
    }

    private func rubberBand(_ offset: CGFloat, width: CGFloat) -> CGFloat {
        let isAtStart = model.currentSpaceIndex == 0 && offset > 0
        let isAtEnd = model.currentSpaceIndex == model.spaces.count - 1 && offset < 0
        return isAtStart || isAtEnd ? offset / 4 : offset
    }

    private func finishSwipe(_ offset: CGFloat, width: CGFloat) {
        let shouldCreateSpace = model.newSpacePullProgress >= 1
        model.newSpacePullProgress = 0
        if shouldCreateSpace {
            withAnimation(Motion.spring(reduceMotion: reduceMotion)) { dragOffset = 0 }
            return model.isNewSpacePresented = true
        }
        let shouldChange = abs(offset) > width * LayoutConstants.swipeCommitThreshold
        withAnimation(Motion.spring(reduceMotion: reduceMotion)) {
            dragOffset = 0
            guard shouldChange else { return }
            model.switchSpace(by: offset < 0 ? 1 : -1)
        }
    }
}

struct NewSpaceSwipeIndicator: View {
    private static let diameter: CGFloat = 60
    private static let ringWidth: CGFloat = 4
    private static let ringInset: CGFloat = 2

    let progress: CGFloat

    private var isReady: Bool { progress >= 1 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(.regularMaterial)
                Circle()
                    .fill(Color.primary.opacity(0.14))
                    .scaleEffect(progress)
                Circle().stroke(Color.primary.opacity(0.2), lineWidth: Self.ringWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: isReady ? "checkmark" : "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.3 + 0.6 * progress))
            }
            .frame(width: Self.diameter - Self.ringInset, height: Self.diameter - Self.ringInset)
            .frame(width: Self.diameter, height: Self.diameter)
            Text(isReady ? "Suelta para crear" : "Sigue empujando")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .scaleEffect(0.75 + 0.25 * progress)
        .opacity(progress > 0 ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SwipeMonitor: NSViewRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> SwipeMonitorView {
        let view = SwipeMonitorView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: SwipeMonitorView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }
}

final class SwipeMonitorView: NSView {
    var onChange: ((CGFloat) -> Void)?
    var onEnd: ((CGFloat) -> Void)?
    private var monitor: Any?
    private var accumulatedDelta: CGFloat = 0
    private var isTrackingHorizontal = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, event.hasPreciseScrollingDeltas else { return event }
        let location = convert(event.locationInWindow, from: nil)
        let isMomentum = event.momentumPhase != []
        if isMomentum { return isTrackingHorizontal ? nil : event }
        if event.phase == .began {
            guard bounds.contains(location) else { return event }
            isTrackingHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            accumulatedDelta = 0
        }
        guard isTrackingHorizontal else { return event }
        switch event.phase {
        case .began, .changed:
            accumulatedDelta += event.scrollingDeltaX
            onChange?(accumulatedDelta)
        case .ended, .cancelled:
            onEnd?(accumulatedDelta)
            isTrackingHorizontal = false
        default:
            break
        }
        return nil
    }
}

struct SpaceContentView: View {
    @Bindable var model: WindowModel
    @Bindable var space: Space
    @ViewState private var isPinnedDropTargeted = false
    @ViewState private var isTodayDropTargeted = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 1) {
                SpaceTitleRow(model: model, space: space)
                ForEach(space.pinned) { node in
                    SidebarNodeRow(model: model, node: node, depth: 0)
                }
                if space.pinned.isEmpty && !model.isPrivate {
                    Text("Arrastra pestañas aquí para fijarlas")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(isPinnedDropTargeted ? 0.35 : 0.12), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .dropDestination(for: String.self) { items, _ in
                            SidebarDrop.handle(items, model: model, container: .pinned(spaceID: space.id), index: nil)
                        } isTargeted: { isPinnedDropTargeted = $0 }
                }
                TodayDivider(model: model, space: space)
                    .dropDestination(for: String.self) { items, _ in
                        SidebarDrop.handle(items, model: model, container: .today(spaceID: space.id), index: 0)
                    } isTargeted: { isTodayDropTargeted = $0 }
                NewTabRow(model: model)
                ForEach(space.today) { node in
                    SidebarNodeRow(model: model, node: node, depth: 0)
                }
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in
                        SidebarDrop.handle(items, model: model, container: .today(spaceID: space.id), index: nil)
                    }
            }
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }
}

struct SpaceTitleRow: View {
    @Bindable var model: WindowModel
    @Bindable var space: Space

    var body: some View {
        HStack(spacing: 6) {
            Text(space.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if let profile = BrowserStore.shared.profile(for: space), profile.name != space.title, !model.isPrivate {
                Text(profile.name)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .contentShape(Rectangle())
        .contextMenu {
            if !model.isPrivate { NativeMenuItems(entries: SpaceMenu.entries(model: model, space: space)) }
        }
    }
}

struct TodayDivider: View {
    @Bindable var model: WindowModel
    @Bindable var space: Space
    @ViewState private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1)
            if isHovering && !space.today.isEmpty {
                Button("Limpiar") { clearToday() }
                    .buttonStyle(.plain)
                    .clickable()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cerrar todas las pestañas de hoy")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private func clearToday() {
        let todayNodes = space.today
        todayNodes.forEach(model.close)
    }
}

struct NewTabRow: View {
    @Bindable var model: WindowModel
    @ViewState private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 16)
            Text("Nueva pestaña").font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: LayoutConstants.rowCornerRadius, style: .continuous).fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture { _ = model.openInNewTab(nil) }
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Nueva pestaña")
    }
}

@MainActor
enum SpaceDeletion {
    static func confirm(_ space: Space, model: WindowModel) {
        let alert = NSAlert()
        alert.messageText = "¿Eliminar el Space \(space.title)?"
        alert.informativeText = "Se cerrarán sus pestañas fijadas y de hoy. El perfil y sus sesiones se conservan."
        alert.addButton(withTitle: "Eliminar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if model.selectedSpaceID == space.id { model.switchSpace(by: model.currentSpaceIndex == 0 ? 1 : -1) }
        BrowserStore.shared.deleteSpace(space.id)
    }
}
