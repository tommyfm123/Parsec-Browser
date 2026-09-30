import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    static let outerInset = SidebarViewMetrics.outerInset
    static let pinnedHeaderTopPadding: CGFloat = 12
    static let floatingHeaderTopPadding: CGFloat = 4
    static let headerHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 12
    static let trafficLightsCenterY = pinnedHeaderTopPadding + headerHeight / 2

    @Bindable var model: WindowModel
    var isFloating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarHeader(model: model)
            AddressBar(model: model)
            if !model.isPrivate {
                FavoritesGrid(model: model)
                    .opacity(1 - model.newSpacePullProgress)
            }
            SpacePager(model: model)
            SidebarFooter(model: model)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, isFloating ? Self.floatingHeaderTopPadding : Self.pinnedHeaderTopPadding)
        .padding(.bottom, 8)
        .frame(width: model.sidebarWidth)
        .frame(maxHeight: .infinity)
        .modifier(FloatingSidebarChrome(theme: model.currentSpace.theme, isFloating: isFloating))
        .overlay(alignment: .trailing) { SidebarResizeHandle(model: model) }
        .themedForeground(model.currentSpace.theme)
    }
}

struct FloatingSidebarChrome: ViewModifier {
    let theme: SpaceTheme
    let isFloating: Bool

    func body(content: Content) -> some View {
        if isFloating {
            content
                .background(SpaceBackgroundView(theme: theme, isGlass: true))
                .clipShape(RoundedRectangle(cornerRadius: Radius.window, style: .continuous))
                .glassEffect(.regular.tint(theme.colors.first?.color.opacity(0.2)), in: RoundedRectangle(cornerRadius: Radius.window, style: .continuous))
                .shadow(color: .black.opacity(0.24), radius: 26, x: 6, y: 4)
        } else {
            content
        }
    }
}

struct SidebarResizeHandle: View {
    @Bindable var model: WindowModel
    @ViewState private var widthAtDragStart: Double?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .offset(x: 4)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let startWidth = widthAtDragStart ?? model.store.settings.sidebarWidth
                        widthAtDragStart = startWidth
                        let proposedWidth = startWidth + value.translation.width
                        model.store.settings.sidebarWidth = min(max(proposedWidth, BrowserSettings.sidebarWidthRange.lowerBound), BrowserSettings.sidebarWidthRange.upperBound)
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                        model.store.saveSoon()
                    }
            )
            .accessibilityLabel("Ajustar ancho del sidebar")
    }
}

struct SidebarHeader: View {
    @Bindable var model: WindowModel

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 76)
            IconButton(symbolName: "arrow.left", label: "Atrás (⌘[)", isEnabled: model.activePage?.canGoBack == true) { model.goBack() }
            IconButton(symbolName: "arrow.right", label: "Adelante (⌘])", isEnabled: model.activePage?.canGoForward == true) { model.goForward() }
            BrowserMoreMenu(model: model)
        }
        .frame(height: SidebarView.headerHeight)
        .background(WindowDragArea())
    }
}

struct BrowserMoreMenu: View {
    @Bindable var model: WindowModel

    var body: some View {
        ParsecDropdown(entries: entries) {
            DropdownIconLabel(symbolName: "ellipsis")
        }
        .help("Más opciones")
        .accessibilityLabel("Más opciones")
    }

    private func entries() -> [MenuEntry] {
        let hasPage = model.activePage != nil
        let assistantName = model.store.settings.assistantProvider.assistantName
        return [
            .action("Recargar", symbol: "arrow.clockwise", shortcut: "⌘R", isEnabled: hasPage) { model.reload() },
            .action("Copiar URL", symbol: "link", shortcut: "⇧⌘C", isEnabled: hasPage) { model.copyCurrentURL() },
            .action("Buscar en la página", symbol: "text.magnifyingglass", shortcut: "⌘F", isEnabled: hasPage) { model.isFindBarVisible = true },
            .divider,
            .action("Acercar", symbol: "plus.magnifyingglass", shortcut: "⌘+", keepsOpen: true) { model.zoomIn() },
            .action("Alejar", symbol: "minus.magnifyingglass", shortcut: "⌘−", keepsOpen: true) { model.zoomOut() },
            .divider,
            .action("Preguntar a \(assistantName)", symbol: "sparkle", shortcut: "⌘J") { model.isAssistantPresented.toggle() },
            .action("Nueva ventana privada", symbol: "eyeglasses", shortcut: "⇧⌘N") { AppDelegate.shared.openPrivateWindow() },
            .action("Pestañas arriba", symbol: "rectangle.topthird.inset.filled", shortcut: "⌥⌘S") { CommandRouter.toggleLayout() },
            .divider,
            .action("Configuración", symbol: "gearshape", shortcut: "⌘,") { AppDelegate.shared.openSettings() },
        ]
    }
}

struct AddressBar: View {
    @Bindable var model: WindowModel
    var height: CGFloat = 36
    var alwaysShowsFullURL = false
    @ViewState private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var displayText: String {
        guard let page = model.activePage, let url = page.currentURL else { return "Buscar o escribir URL" }
        guard !alwaysShowsFullURL, !model.store.settings.showsFullURL else { return url.absoluteString }
        return (url.host() ?? url.absoluteString).replacingOccurrences(of: WebConstants.wwwPrefix, with: "")
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.isSitePopoverPresented = true
            } label: {
                Image(systemName: model.activePage?.currentURL?.scheme == WebConstants.httpsScheme ? "lock.fill" : "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.activePage == nil)
            .help("Configuración del sitio")
            .accessibilityLabel("Configuración del sitio")
            .popover(isPresented: $model.isSitePopoverPresented, arrowEdge: .bottom) {
                SitePopoverView(model: model)
            }
            Text(displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(model.activePage?.currentURL == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.activePage?.hasSavedCredentials == true {
                IconButton(symbolName: "key.fill", label: "Rellenar contraseña (⌘\\)") { model.fillPassword() }
            }
            if model.isPrivate {
                Image(systemName: "eyeglasses").font(.system(size: 12)).help("Ventana privada")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous)
                .fill(SidebarPalette.controlFill(colorScheme, isActive: isHovering))
        )
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture { model.presentCommandBar(mode: .navigateCurrent) }
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Dirección: \(displayText)")
    }
}

enum SidebarPalette {
    static func controlFill(_ colorScheme: ColorScheme, isActive: Bool) -> Color {
        colorScheme == .dark ? Color.white.opacity(isActive ? 0.12 : 0.07) : Color.black.opacity(isActive ? 0.08 : 0.05)
    }

    static func selectedTileFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.85)
    }

    static func rowFill(_ colorScheme: ColorScheme, isSelected: Bool, isHovering: Bool) -> Color {
        let darkOpacity = isSelected ? 0.16 : isHovering ? 0.07 : 0
        let lightOpacity = isSelected ? 0.82 : isHovering ? 0.35 : 0
        return colorScheme == .dark ? Color.white.opacity(darkOpacity) : Color.white.opacity(lightOpacity)
    }
}

struct FavoritesGrid: View {
    private static let spacing: CGFloat = 6
    private static let preferredTileWidth: CGFloat = 60
    private static let minimumColumns = 3
    private static let maximumRows = 3
    private static let tileHeight: CGFloat = 40

    @Bindable var model: WindowModel
    @ViewState private var isDropTargeted = false
    @ViewState private var pageIndex: Int? = 0

    private var columnCount: Int {
        let innerWidth = model.sidebarWidth - SidebarView.horizontalPadding * 2
        return max(Self.minimumColumns, Int((innerWidth + Self.spacing) / (Self.preferredTileWidth + Self.spacing)))
    }

    private var pagedHeight: CGFloat {
        let firstPageCount = pages.first?.count ?? 0
        let rows = CGFloat((firstPageCount + columnCount - 1) / columnCount)
        return rows * Self.tileHeight + max(rows - 1, 0) * Self.spacing
    }

    private var pages: [[SidebarNode]] {
        let pageSize = columnCount * Self.maximumRows
        return stride(from: 0, to: model.favorites.count, by: pageSize).map { start in
            Array(model.favorites[start..<min(start + pageSize, model.favorites.count)])
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if pages.count > 1 {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { index in
                            page(pages[index])
                                .containerRelativeFrame(.horizontal)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.never)
                .scrollPosition(id: $pageIndex)
                .frame(height: pagedHeight)
                PageDots(count: pages.count, selection: $pageIndex)
            } else {
                page(pages.first ?? [])
            }
        }
        .frame(minHeight: model.favorites.isEmpty ? 30 : nil)
        .overlay {
            if model.favorites.isEmpty {
                Text("Arrastra aquí tus favoritos")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous).strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.6 : 0), lineWidth: 1.5))
        .dropDestination(for: String.self) { items, _ in
            SidebarDrop.handle(items, model: model, container: .favorites(profileID: model.currentSpace.profileID), index: nil)
        } isTargeted: { isDropTargeted = $0 }
    }

    private func page(_ nodes: [SidebarNode]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columnCount), spacing: Self.spacing) {
            ForEach(nodes) { node in
                FavoriteTile(model: model, node: node)
            }
        }
    }
}

struct PageDots: View {
    let count: Int
    @Binding var selection: Int?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button { withAnimation(.snappy) { selection = index } } label: {
                    Circle()
                        .fill(Color.primary.opacity((selection ?? 0) == index ? 0.55 : 0.18))
                        .frame(width: 5, height: 5)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Página \(index + 1) de \(count)")
            }
        }
    }
}

struct FavoriteTile: View {
    @Bindable var model: WindowModel
    let node: SidebarNode
    @ViewState private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var isSelected: Bool { model.currentSpace.selectedNodeID == node.id }

    var body: some View {
        FaviconView(url: node.liveURL ?? node.children.first?.liveURL, size: 18)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous)
                    .fill(isSelected ? SidebarPalette.selectedTileFill(colorScheme) : SidebarPalette.controlFill(colorScheme, isActive: isHovering))
                    .shadow(color: .black.opacity(isSelected ? 0.1 : 0), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.12 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .clickable()
            .onTapGesture { model.select(node) }
            .onHover { isHovering = $0 }
            .help(node.displayTitle)
            .accessibilityLabel(node.displayTitle)
            .accessibilityAddTraits(.isButton)
            .draggable(node.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                SidebarDrop.handle(items, model: model, onto: node)
            }
            .contextMenu { NodeContextMenu(model: model, node: node) }
    }
}

struct SidebarFooter: View {
    @Bindable var model: WindowModel
    @ViewState private var isDownloadsPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            IconButton(symbolName: DownloadManager.shared.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle", label: "Descargas") {
                isDownloadsPresented = true
            }
            .popover(isPresented: $isDownloadsPresented, arrowEdge: .top) { DownloadsView() }
            ClaudeButton(model: model)
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(Array(model.spaces.enumerated()), id: \.element.id) { index, space in
                            SpaceDot(model: model, space: space, isSelected: space.id == model.selectedSpaceID) {
                                withAnimation(Motion.spring(reduceMotion: reduceMotion)) { model.switchToSpace(at: index) }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .popover(isPresented: $model.isThemeEditorPresented, arrowEdge: .top) { ArcThemeEditor(space: model.currentSpace) }
            .popover(isPresented: Binding(get: { model.spaceIconEditingID != nil }, set: { if !$0 { model.spaceIconEditingID = nil } }), arrowEdge: .top) {
                SpaceIconPicker(space: model.currentSpace) { model.spaceIconEditingID = nil }
            }
            Spacer(minLength: 0)
            NewItemMenu(model: model)
        }
        .frame(height: 30)
    }
}

struct ClaudeButton: View {
    @Bindable var model: WindowModel

    var body: some View {
        Button { model.isAssistantPresented.toggle() } label: {
            FaviconView(url: model.store.settings.assistantProvider.logoURL, size: 15)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(isActive: model.isAssistantPresented)
        .help("Preguntar a \(model.store.settings.assistantProvider.assistantName) (⌘J)")
        .accessibilityLabel("Preguntar a \(model.store.settings.assistantProvider.assistantName)")
    }
}

struct NewItemMenu: View {
    @Bindable var model: WindowModel

    var body: some View {
        ParsecDropdown(arrowEdge: .top, entries: entries) {
            DropdownIconLabel(symbolName: "plus")
        }
        .help("Nuevo")
        .accessibilityLabel("Nuevo")
    }

    private func entries() -> [MenuEntry] {
        let assistantName = model.store.settings.assistantProvider.assistantName
        return [
            .action("Nueva pestaña", symbol: "plus.square", shortcut: "⌘T") { model.presentCommandBar(mode: .newTab) },
            .action("Nueva vista dividida", symbol: "rectangle.split.2x1", shortcut: "⌃⌘=", isEnabled: !model.isPrivate && model.selectedNode != nil) { model.splitView() },
            .divider,
            .action("Nuevo Space", symbol: "plus.square.on.square", shortcut: "⌥⌘N", isEnabled: !model.isPrivate) { model.isNewSpacePresented = true },
            .action("Nueva carpeta", symbol: "folder.badge.plus", isEnabled: !model.isPrivate) { model.createFolder(in: .pinned(spaceID: model.currentSpace.id)) },
            .divider,
            .action("Preguntar a \(assistantName)", symbol: "sparkle", shortcut: "⌘J") { model.isAssistantPresented = true },
        ]
    }
}

struct SpaceDot: View {
    @Bindable var model: WindowModel
    let space: Space
    let isSelected: Bool
    let action: () -> Void
    @ViewState private var isHovering = false

    var body: some View {
        Group {
            if isSelected && !model.isPrivate {
                ParsecDropdown(arrowEdge: .top) { SpaceMenu.entries(model: model, space: space) } label: { dot }
            } else {
                Button(action: action) { dot }.buttonStyle(.plain)
            }
        }
        .hoverHighlight()
        .onHover { isHovering = $0 }
        .contextMenu {
            if !model.isPrivate { NativeMenuItems(entries: SpaceMenu.entries(model: model, space: space)) }
        }
        .help(isSelected ? "\(space.title) — clic para editar" : space.title)
        .accessibilityLabel("Space \(space.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dot: some View {
        Group {
            if let iconSymbol = space.iconSymbol {
                Image(systemName: iconSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(isSelected ? 0.8 : isHovering ? 0.5 : 0.32))
            } else {
                Circle()
                    .fill(Color.primary.opacity(isSelected ? 0.62 : isHovering ? 0.35 : 0.2))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
