import SwiftUI

struct ContentAreaView: View {
    @Bindable var model: WindowModel
    let cornerRadius: CGFloat
    @ViewState private var isSplitDropTargeted = false

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let node = model.selectedNode {
                    if node.isSplit {
                        SplitPanesView(model: model, split: node, outerPadding: cornerRadius > 0 ? 0 : 8)
                    } else {
                        SinglePaneView(model: model, node: node, cornerRadius: cornerRadius)
                    }
                } else {
                    StartPageView(model: model, cornerRadius: cornerRadius > 0 ? cornerRadius : Radius.card)
                }
            }
            .id(model.selectedNode?.id)
            if isSplitDropTargeted {
                SplitDropHint()
            }
            if model.isFindBarVisible {
                FindBarView(model: model)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            if let nodeID = UUID(uuidString: payload) {
                model.addToSplit(nodeID)
                return true
            }
            guard let url = URL(string: payload), url.scheme != nil else { return false }
            _ = model.openInNewTab(url)
            return true
        } isTargeted: { isSplitDropTargeted = $0 }
    }
}

struct SinglePaneView: View {
    @Bindable var model: WindowModel
    @Bindable var node: SidebarNode
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if let conversation = model.pageConversations[node.id] {
                ConversationPageView(model: model, conversation: conversation, cornerRadius: cornerRadius > 0 ? cornerRadius : Radius.card)
            } else if node.url == nil && node.page?.currentURL == nil {
                StartPageView(model: model, cornerRadius: cornerRadius > 0 ? cornerRadius : Radius.card, targetNodeID: node.id)
            } else {
                PaneWebContent(model: model, node: node, cornerRadius: cornerRadius, roundsTopCorners: true)
                LoadingLineView(page: node.page)
            }
        }
        .shadow(color: .black.opacity(cornerRadius > 0 ? 0.12 : 0), radius: 10, y: 2)
    }
}

struct PaneWebContent: View {
    @Bindable var model: WindowModel
    @Bindable var node: SidebarNode
    let cornerRadius: CGFloat
    let roundsTopCorners: Bool

    var body: some View {
        if let page = node.page {
            ZStack {
                WebViewHost(webView: page.webView, cornerRadius: cornerRadius, roundsTopCorners: roundsTopCorners)
                if let activity = page.agentActivity {
                    AgentDrivingOverlay(activity: activity, cornerRadius: cornerRadius) {
                        model.agents.filter(\.isRunning).forEach { $0.stop() }
                    }
                }
                if node.url == nil && page.currentURL == nil {
                    BlankPaneView(cornerRadius: cornerRadius, roundsTopCorners: roundsTopCorners) {
                        model.focusPane(node.id)
                        model.presentCommandBar(mode: .navigate(nodeID: node.id))
                    }
                }
            }
        } else {
            UnevenRoundedRectangle(cornerRadii: paneRadii(cornerRadius, roundsTopCorners: roundsTopCorners), style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .onAppear { model.loadPage(for: node) }
        }
    }
}

struct AgentDrivingOverlay: View {
    let activity: String
    let cornerRadius: CGFloat
    let onStop: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            IntelligenceGlow(isActive: true, cornerRadius: cornerRadius)
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.motionlines").font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Parsec está navegando").font(.system(size: 12, weight: .semibold))
                    Text(activity).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: 280, alignment: .leading)
                Button("Detener", action: onStop)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.snappy, value: activity)
    }
}

func paneRadii(_ radius: CGFloat, roundsTopCorners: Bool) -> RectangleCornerRadii {
    let topRadius = roundsTopCorners ? radius : 0
    return RectangleCornerRadii(topLeading: topRadius, bottomLeading: radius, bottomTrailing: radius, topTrailing: topRadius)
}

struct SplitPanesView: View {
    private static let gutter: CGFloat = 8
    private static let minimumFraction: CGFloat = 0.15

    @Bindable var model: WindowModel
    @Bindable var split: SidebarNode
    let outerPadding: CGFloat
    @ViewState private var fractions: [CGFloat] = []

    private var resolvedFractions: [CGFloat] {
        let paneCount = split.children.count
        guard fractions.count == paneCount else { return Array(repeating: 1 / CGFloat(max(paneCount, 1)), count: paneCount) }
        return fractions
    }

    var body: some View {
        GeometryReader { geometry in
            let dividerCount = CGFloat(max(split.children.count - 1, 0))
            let availableWidth = geometry.size.width - Self.gutter * dividerCount - outerPadding * 2
            HStack(spacing: 0) {
                ForEach(Array(split.children.enumerated()), id: \.element.id) { index, pane in
                    if index > 0 {
                        SplitDivider(width: Self.gutter) { translation in
                            resize(dividerIndex: index, translation: translation, availableWidth: availableWidth)
                        }
                    }
                    SplitPaneCard(model: model, pane: pane, isFocused: pane.id == model.focusedPaneID)
                        .frame(width: max(availableWidth * resolvedFractions[index], 0))
                }
            }
            .padding(outerPadding)
        }
    }

    private func resize(dividerIndex: Int, translation: CGFloat, availableWidth: CGFloat) {
        var updated = resolvedFractions
        let delta = translation / max(availableWidth, 1)
        let leading = updated[dividerIndex - 1] + delta
        let trailing = updated[dividerIndex] - delta
        guard leading >= Self.minimumFraction, trailing >= Self.minimumFraction else { return }
        updated[dividerIndex - 1] = leading
        updated[dividerIndex] = trailing
        fractions = updated
    }
}

struct SplitPaneCard: View {
    @Bindable var model: WindowModel
    @Bindable var pane: SidebarNode
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaneToolbar(model: model, pane: pane)
            ZStack(alignment: .top) {
                PaneWebContent(model: model, node: pane, cornerRadius: Radius.card, roundsTopCorners: false)
                LoadingLineView(page: pane.page)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: isFocused ? 1.5 : 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(isFocused ? 0.16 : 0.08), radius: isFocused ? 14 : 6, y: 3)
    }
}

struct PaneToolbar: View {
    @Bindable var model: WindowModel
    @Bindable var pane: SidebarNode

    private var page: WebPage? { pane.page }

    var body: some View {
        HStack(spacing: 2) {
            IconButton(symbolName: "chevron.left", label: "Atrás", isEnabled: page?.canGoBack == true) { page?.webView.goBack() }
            IconButton(symbolName: "chevron.right", label: "Adelante", isEnabled: page?.canGoForward == true) { page?.webView.goForward() }
            IconButton(symbolName: "arrow.clockwise", label: "Recargar", isEnabled: page != nil) { page?.webView.reload() }
            HStack(spacing: 6) {
                FaviconView(url: pane.liveURL, size: 13)
                Text(pane.displayHost.isEmpty ? "Nuevo panel" : pane.displayHost)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                model.focusPane(pane.id)
                model.presentCommandBar(mode: .navigate(nodeID: pane.id))
            }
            IconButton(symbolName: "xmark", label: "Cerrar panel (⌃⌘W)") {
                model.focusPane(pane.id)
                model.closeFocusedPane()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(
            UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: Radius.card, topTrailing: Radius.card), style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
        .simultaneousGesture(TapGesture().onEnded { model.focusPane(pane.id) })
    }
}

struct SplitDivider: View {
    let width: CGFloat
    let onDrag: (CGFloat) -> Void
    @ViewState private var lastTranslation: CGFloat = 0
    @ViewState private var isHovering = false
    @ViewState private var isDragging = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.primary.opacity(isDragging ? 0.45 : 0.25))
                .frame(width: 3, height: 36)
                .opacity(isHovering || isDragging ? 1 : 0)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    onDrag(value.translation.width - lastTranslation)
                    lastTranslation = value.translation.width
                }
                .onEnded { _ in
                    isDragging = false
                    lastTranslation = 0
                }
        )
        .accessibilityLabel("Divisor de paneles")
    }
}

struct BlankPaneView: View {
    let cornerRadius: CGFloat
    let roundsTopCorners: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Button("Elegir qué abrir", action: action)
                .buttonStyle(.glass)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(cornerRadii: paneRadii(cornerRadius, roundsTopCorners: roundsTopCorners), style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }
}

struct SplitDropHint: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.accentColor.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .overlay(Label("Soltar para dividir", systemImage: "rectangle.split.2x1").font(.system(size: 14, weight: .semibold)))
            .padding(10)
            .allowsHitTesting(false)
    }
}

struct FindBarView: View {
    @Bindable var model: WindowModel
    @ViewState private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar en la página", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 190)
                .focused($isFocused)
                .onSubmit { search(backwards: false) }
                .onChange(of: query) { search(backwards: false) }
            if model.findHasNoMatch && !query.isEmpty {
                Text("Sin resultados").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            IconButton(symbolName: "chevron.up", label: "Anterior (⇧⌘G)") { search(backwards: true) }
            IconButton(symbolName: "chevron.down", label: "Siguiente (⌘G)") { search(backwards: false) }
            IconButton(symbolName: "xmark", label: "Cerrar") { model.isFindBarVisible = false }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
        .onAppear { isFocused = true }
    }

    private func search(backwards: Bool) {
        (model.window as? BrowserWindow)?.updateFindQuery(query)
        model.find(query, backwards: backwards)
    }
}

@MainActor
enum BrandMark {
    private static let resourceName = "ParsecMark"

    static let image: NSImage? = {
        let image = Bundle.main.image(forResource: resourceName)
        image?.isTemplate = true
        return image
    }()
}
