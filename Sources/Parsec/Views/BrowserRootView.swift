import SwiftUI

struct BrowserRootView: View {
    @Bindable var model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: BrowserStore { BrowserStore.shared }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch store.settings.layout {
            case .sidebar: SidebarLayoutView(model: model)
            case .topTabs: TopTabsLayoutView(model: model)
            }
            OverlayLayer(model: model)
            if model.isWelcomePresented {
                WelcomeView { model.finishWelcome() }
                    .transition(.opacity)
            }
        }
        .background(WindowBackgroundView(theme: model.currentSpace.theme))
        .ignoresSafeArea()
        .onChange(of: model.isChromeVisible, initial: true) { _, isVisible in
            (model.window as? BrowserWindow)?.setTrafficLightsVisible(isVisible)
        }
        .onChange(of: store.settings.layout, initial: true) { _, layout in
            (model.window as? BrowserWindow)?.trafficLightsCenterY = layout == .topTabs ? LayoutConstants.topBarHeight / 2 : SidebarView.trafficLightsCenterY
        }
        .sheet(isPresented: $model.isNewSpacePresented) {
            NewSpaceView(model: model)
        }
    }
}

struct SidebarLayoutView: View {
    private static let inset = SidebarView.outerInset

    @Bindable var model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPinned: Bool { model.isSidebarPinned }
    private var assistantInset: CGFloat { model.isAssistantPresented ? AssistantPanelView.width + Self.inset : 0 }
    private var usesCardLayout: Bool { isPinned || model.isAssistantPresented }

    var body: some View {
        ZStack(alignment: .leading) {
            ContentAreaView(model: model, cornerRadius: usesCardLayout ? Radius.card : 0)
                .padding(.leading, isPinned ? model.sidebarWidth : usesCardLayout ? Self.inset : 0)
                .padding(.trailing, usesCardLayout ? Self.inset + assistantInset : 0)
                .padding(.vertical, usesCardLayout ? Self.inset : 0)
            if isPinned {
                SidebarView(model: model)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                Color.clear
                    .frame(width: LayoutConstants.hoverEdgeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { isInside in
                        if isInside { model.isSidebarHovering = true }
                    }
                SidebarView(model: model, isFloating: true)
                    .padding(Self.inset)
                    .offset(x: model.isSidebarHovering ? 0 : -(model.sidebarWidth + 48))
                    .onHover { isInside in
                        if !isInside && model.commandBar == nil { model.isSidebarHovering = false }
                    }
            }
            AssistantEdge(model: model)
        }
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.isSidebarHovering)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: isPinned)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.isAssistantPresented)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.isAssistantHovering)
    }
}

struct AssistantEdge: View {
    @Bindable var model: WindowModel

    var body: some View {
        ZStack(alignment: .trailing) {
            if model.isAssistantPresented {
                AssistantPanelView(model: model, assistant: model.assistant)
                    .padding(SidebarView.outerInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Color.clear
                    .frame(width: LayoutConstants.hoverEdgeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { isInside in
                        if isInside { model.isAssistantHovering = true }
                    }
                AssistantPanelView(model: model, assistant: model.assistant, isFloating: true)
                    .padding(SidebarView.outerInset)
                    .offset(x: model.isAssistantHovering ? 0 : AssistantPanelView.width + 48)
                    .onHover { isInside in
                        if !isInside { model.isAssistantHovering = false }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

struct TopTabsLayoutView: View {
    @Bindable var model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if model.isSidebarPinned {
                    TopTabsBar(model: model)
                        .transition(.move(edge: .top))
                }
                ContentAreaView(model: model, cornerRadius: 0)
            }
            if !model.isSidebarPinned {
                Color.clear
                    .frame(height: LayoutConstants.hoverEdgeWidth)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { isInside in
                        if isInside { model.isSidebarHovering = true }
                    }
                TopTabsBar(model: model)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
                    .offset(y: model.isSidebarHovering ? 0 : -(LayoutConstants.topBarHeight + 24))
                    .onHover { isInside in
                        if !isInside && model.commandBar == nil { model.isSidebarHovering = false }
                    }
            }
        }
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.isSidebarHovering)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.isSidebarPinned)
    }
}

struct TopTabsBar: View {
    private static let namedFolderLimit = 4
    private static let favoriteLimit = 8

    @Bindable var model: WindowModel

    private var openTabs: [SidebarNode] {
        let loadedPinned = model.currentSpace.pinned.flatMap(openNodes)
        return loadedPinned + model.currentSpace.today
    }

    private var folders: [SidebarNode] {
        model.currentSpace.pinned.filter(\.isFolder)
    }

    private static let trafficLightsReservedWidth: CGFloat = 78
    private static let controlHeight: CGFloat = 32
    private static let addressWidth: CGFloat = 250

    var body: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: Self.trafficLightsReservedWidth)
            IconButton(symbolName: "arrow.left", label: "Atrás", isEnabled: model.activePage?.canGoBack == true) { model.goBack() }
            IconButton(symbolName: "arrow.right", label: "Adelante", isEnabled: model.activePage?.canGoForward == true) { model.goForward() }
            AddressBar(model: model, height: Self.controlHeight)
                .frame(width: Self.addressWidth)
                .padding(.leading, 6)
            if !model.favorites.isEmpty {
                TopBarDivider()
                ForEach(model.favorites.prefix(Self.favoriteLimit)) { node in
                    Button { model.select(node) } label: {
                        FaviconView(url: node.liveURL, size: 15)
                            .frame(width: Self.controlHeight, height: Self.controlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(cornerRadius: 8, isActive: model.currentSpace.selectedNodeID == node.id)
                    .help(node.displayTitle)
                    .accessibilityLabel(node.displayTitle)
                }
            }
            if !folders.isEmpty {
                TopBarDivider()
                ForEach(folders) { folder in
                    TopFolderMenu(model: model, folder: folder, showsTitle: folders.count <= Self.namedFolderLimit)
                }
            }
            TopBarDivider()
            TopTabStrip(model: model, tabs: openTabs)
            TopSpaceMenu(model: model)
            IconButton(symbolName: "plus", label: "Nueva pestaña (⌘T)") { model.presentCommandBar(mode: .newTab) }
            IconButton(symbolName: model.isSidebarPinned ? "pin.fill" : "pin", label: "Fijar barra (⌘S)") { model.toggleSidebarPinned() }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: LayoutConstants.topBarHeight)
        .background(SpaceBackgroundView(theme: model.currentSpace.theme))
        .background(WindowDragArea())
        .themedForeground(model.currentSpace.theme)
    }

    private func openNodes(_ node: SidebarNode) -> [SidebarNode] {
        guard node.isFolder else { return node.allTabs.contains { $0.page != nil } ? [node] : [] }
        return node.children.flatMap(openNodes)
    }
}

struct TopBarDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 6)
    }
}

struct TopBarPill<Label: View>: View {
    var isActive = false
    @ViewBuilder let label: Label

    var body: some View {
        HStack(spacing: 6) { label }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(isActive ? 0.1 : 0)))
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: 8)
    }
}

struct TopFolderMenu: View {
    @Bindable var model: WindowModel
    let folder: SidebarNode
    let showsTitle: Bool

    private var containsSelection: Bool {
        folder.allTabs.contains { $0.id == model.currentSpace.selectedNodeID }
    }

    var body: some View {
        ParsecDropdown(width: 280) {
            folder.allTabs.map { tab in
                MenuEntry.action(tab.displayTitle, iconURL: tab.liveURL, isSelected: tab.id == model.currentSpace.selectedNodeID) { model.select(tab) }
            }
        } label: {
            TopBarPill(isActive: containsSelection) {
                FolderIconView(symbolName: folder.iconSymbol, size: 14)
                if showsTitle {
                    Text(folder.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .help(folder.title)
        .accessibilityLabel("Carpeta \(folder.title)")
    }
}

struct TopSpaceMenu: View {
    @Bindable var model: WindowModel

    var body: some View {
        ParsecDropdown {
            [MenuEntry.header("Spaces")]
                + model.spaces.enumerated().map { index, space in
                    MenuEntry.action(space.title, symbol: space.iconSymbol ?? "circle.fill", isSelected: space.id == model.currentSpace.id) { model.switchToSpace(at: index) }
                }
                + [.divider]
                + SpaceMenu.entries(model: model, space: model.currentSpace)
        } label: {
            TopBarPill {
                Circle()
                    .fill(model.currentSpace.theme.colors.first?.color ?? .gray)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                Text(model.currentSpace.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $model.isThemeEditorPresented, arrowEdge: .bottom) { ArcThemeEditor(space: model.currentSpace) }
        .help("Cambiar de Space")
    }
}

struct TopTabStrip: View {
    private static let minimumTabWidth: CGFloat = 110
    private static let maximumTabWidth: CGFloat = 220
    private static let spacing: CGFloat = 4

    @Bindable var model: WindowModel
    let tabs: [SidebarNode]

    var body: some View {
        GeometryReader { geometry in
            let count = CGFloat(max(tabs.count, 1))
            let fittedWidth = (geometry.size.width - Self.spacing * (count - 1)) / count
            let tabWidth = min(max(fittedWidth, Self.minimumTabWidth), Self.maximumTabWidth)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.spacing) {
                    ForEach(tabs) { node in
                        TopTabChip(model: model, node: node, width: tabWidth)
                    }
                }
                .frame(height: geometry.size.height)
            }
        }
        .frame(height: 32)
        .padding(.trailing, 6)
    }
}

struct TopTabChip: View {
    @Bindable var model: WindowModel
    @Bindable var node: SidebarNode
    let width: CGFloat
    @ViewState private var isHovering = false
    @ViewState private var isDropTargeted = false

    private var isSelected: Bool { model.currentSpace.selectedNodeID == node.id }
    private var showsClose: Bool { isSelected || isHovering }

    var body: some View {
        HStack(spacing: 6) {
            FaviconView(url: node.liveURL ?? node.children.first?.liveURL, size: 14)
            Text(node.isSplit ? node.children.map(\.displayTitle).joined(separator: " | ") : node.displayTitle)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { model.close(node) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(showsClose ? 1 : 0)
            .accessibilityLabel("Cerrar \(node.displayTitle)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: width, height: 32, alignment: .leading)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .dropIndicator(isDropTargeted, axis: .vertical)
        .contentShape(Rectangle())
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .clickable()
        .onTapGesture { model.select(node) }
        .onHover { isHovering = $0 }
        .draggable(node.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            SidebarDrop.handle(items, model: model, onto: node)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu { NodeContextMenu(model: model, node: node) }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct OverlayLayer: View {
    @Bindable var model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let peek = model.peek {
                PeekView(model: model, node: peek.node)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let commandBar = model.commandBar {
                CommandBarView(model: model, commandBar: commandBar)
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
            if model.isHistoryPresented {
                ConversationHistoryView(model: model)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
            VStack(spacing: 8) {
                if let request = model.permissionRequest {
                    PromptCard(
                        symbolName: request.kind == .microphone ? "mic.fill" : "video.fill",
                        message: "\(request.host) quiere usar \(request.kind.label)",
                        primaryTitle: "Permitir",
                        secondaryTitle: "Bloquear",
                        onPrimary: { model.resolvePermission(true) },
                        onSecondary: { model.resolvePermission(false) }
                    )
                }
                if let offer = model.passwordOffer {
                    PromptCard(
                        symbolName: "key.fill",
                        message: "¿Guardar la contraseña de \(offer.username.isEmpty ? offer.host : offer.username) en el Llavero?",
                        primaryTitle: "Guardar",
                        secondaryTitle: "Ahora no",
                        tertiaryTitle: "Nunca en este sitio",
                        onPrimary: { model.resolvePasswordOffer(save: true) },
                        onSecondary: { model.resolvePasswordOffer(save: false) },
                        onTertiary: { model.resolvePasswordOffer(save: false, never: true) }
                    )
                }
                if !model.credentialChoices.isEmpty {
                    CredentialChooser(model: model)
                }
                Spacer()
                if let toast = model.toast {
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
            }
            .padding(.top, 16)
        }
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.commandBar != nil)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.isHistoryPresented)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.peek?.id)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.toast)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.permissionRequest?.id)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.passwordOffer?.id)
    }
}

struct PromptCard: View {
    let symbolName: String
    let message: String
    let primaryTitle: String
    let secondaryTitle: String
    var tertiaryTitle: String?
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    var onTertiary: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName).font(.system(size: 16)).foregroundStyle(Color.accentColor)
            Text(message).font(.system(size: 13)).lineLimit(2).frame(maxWidth: 320, alignment: .leading)
            if let tertiaryTitle, let onTertiary {
                Button(tertiaryTitle, action: onTertiary).buttonStyle(.borderless)
            }
            Button(secondaryTitle, action: onSecondary).buttonStyle(.bordered)
            Button(primaryTitle, action: onPrimary).buttonStyle(.borderedProminent)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct CredentialChooser: View {
    @Bindable var model: WindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Elegir cuenta").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(model.credentialChoices) { credential in
                Button { model.fill(credential) } label: {
                    Label(credential.account.isEmpty ? "(sin usuario)" : credential.account, systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            Button("Cancelar") { model.credentialChoices = [] }.buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }
}

struct WindowBackgroundView: View {
    let theme: SpaceTheme

    var body: some View {
        SpaceBackgroundView(theme: theme)
    }
}
