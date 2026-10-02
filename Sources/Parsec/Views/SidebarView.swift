import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    static let outerInset = SidebarViewMetrics.outerInset
    static let pinnedHeaderTopPadding: CGFloat = 8
    static let floatingHeaderTopPadding: CGFloat = 4
    static let headerHeight: CGFloat = 36
    static let horizontalPadding: CGFloat = 8
    static let trafficLightsCenterY = pinnedHeaderTopPadding + headerHeight / 2

    @Bindable var model: WindowModel
    var isFloating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .background(SpaceBackgroundView(theme: theme, isGlass: true, usesMesh: true))
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
            SidebarCircleButton(symbolName: "chevron.left", label: "Atrás (⌘[)", isEnabled: model.activePage?.canGoBack == true, action: model.goBack)
            SidebarCircleButton(symbolName: "arrow.clockwise", label: "Recargar (⌘R)", isEnabled: model.activePage != nil, action: model.reload)
        }
        .frame(height: SidebarView.headerHeight)
        .background(WindowDragArea())
    }
}

struct SidebarCircleButton: View {
    let symbolName: String
    let label: String
    var isEnabled = true
    let action: () -> Void
    @ViewState private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .frame(width: SidebarView.headerHeight, height: SidebarView.headerHeight)
                .background {
                    Circle().fill(SidebarPalette.glassFill(colorScheme, isActive: isHovering))
                }
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(Color.primary.opacity(isEnabled ? 0.9 : 0.4))
        .clickable()
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

struct BrowserMoreMenu: View {
    @Bindable var model: WindowModel

    var body: some View {
        ParsecDropdown(entries: entries) {
            DropdownIconLabel(symbolName: "slider.horizontal.3")
        }
        .help("Más opciones")
        .accessibilityLabel("Más opciones")
    }

    private func entries() -> [MenuEntry] {
        let hasPage = model.activePage != nil
        let assistantName = model.store.settings.assistantProvider.assistantName
        return [
            .action("Adelante", symbol: "arrow.right", shortcut: "⌘]", isEnabled: model.activePage?.canGoForward == true) { model.goForward() },
            .action("Configuración del sitio", symbol: "lock", isEnabled: hasPage) { model.isSitePopoverPresented = true },
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
        guard let page = model.activePage, let url = page.currentURL else { return "Nueva pestaña" }
        guard !alwaysShowsFullURL, !model.store.settings.showsFullURL else { return url.absoluteString }
        return (url.host() ?? url.absoluteString).replacingOccurrences(of: WebConstants.wwwPrefix, with: "")
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.activePage?.hasSavedCredentials == true {
                IconButton(symbolName: "key.fill", label: "Rellenar contraseña (⌘\\)") { model.fillPassword() }
            }
            if model.isPrivate {
                Image(systemName: "eyeglasses").font(.system(size: 12)).help("Ventana privada")
            }
            BrowserMoreMenu(model: model)
                .foregroundStyle(.secondary)
                .popover(isPresented: $model.isSitePopoverPresented, arrowEdge: .bottom) {
                    SitePopoverView(model: model)
                }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
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
    static let rowHeight: CGFloat = 36
    static let rowCornerRadius: CGFloat = 12

    static func glassFill(_ colorScheme: ColorScheme, isActive: Bool) -> LinearGradient {
        let opacity = colorScheme == .dark ? (isActive ? 0.28 : 0.16) : (isActive ? 0.9 : 0.7)
        return LinearGradient(colors: [Color.white.opacity(opacity), Color.white.opacity(opacity * 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func controlFill(_ colorScheme: ColorScheme, isActive: Bool) -> Color {
        colorScheme == .dark ? Color.white.opacity(isActive ? 0.12 : 0.07) : Color.black.opacity(isActive ? 0.08 : 0.05)
    }

    static func selectedTileFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.85)
    }

    static func rowFill(_ colorScheme: ColorScheme, isSelected: Bool, isHovering: Bool) -> Color {
        let darkOpacity = isSelected ? 0.16 : isHovering ? 0.07 : 0
        let lightOpacity = isSelected ? 0.82 : isHovering ? 0.35 : 0
        return colorScheme == .dark ? Color.white.opacity(darkOpacity) : Color.white.opacity(lightOpacity)
    }
}

struct FavoritesGrid: View {
    private static let spacing = SidebarViewMetrics.favoriteSpacing
    private static let maximumRows = 3
    private static let tileHeight = SidebarViewMetrics.favoriteTileHeight

    @Bindable var model: WindowModel
    @ViewState private var isDropTargeted = false
    @ViewState private var pageIndex: Int? = 0
    @ViewState private var draggedFavoriteID: UUID?
    @ViewState private var previewIDs: [UUID] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayedFavorites: [SidebarNode] {
        guard !previewIDs.isEmpty else { return model.favorites }
        let nodes = Dictionary(uniqueKeysWithValues: model.favorites.map { ($0.id, $0) })
        return previewIDs.compactMap { nodes[$0] }
    }

    private var columnCount: Int {
        let innerWidth = model.sidebarWidth - SidebarView.horizontalPadding * 2
        return SidebarViewMetrics.favoriteColumnCount(availableWidth: innerWidth, favoriteCount: model.favorites.count)
    }

    private var pagedHeight: CGFloat {
        let firstPageCount = pages.first?.count ?? 0
        let rows = CGFloat((firstPageCount + columnCount - 1) / columnCount)
        return rows * Self.tileHeight + max(rows - 1, 0) * Self.spacing
    }

    private var pages: [[SidebarNode]] {
        let pageSize = columnCount * Self.maximumRows
        let favorites = displayedFavorites
        return stride(from: 0, to: favorites.count, by: pageSize).map { start in
            Array(favorites[start..<min(start + pageSize, favorites.count)])
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if pages.count > 1 {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, nodes in
                            page(nodes, index: index)
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
                page(pages.first ?? [], index: 0)
            }
        }
        .frame(minHeight: model.favorites.isEmpty ? Self.tileHeight : nil)
        .overlay {
            if model.favorites.isEmpty {
                Text("Arrastra aquí tus favoritos")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous).strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.6 : 0), lineWidth: 1.5))
        .dragContainer(for: String.self, itemID: \.self) { (ids: [String]) in ids }
        .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: true, allowMove: true), operationsOutsideApp: .init(allowCopy: false)))
        .onDragSessionUpdated { session in
            switch session.phase {
            case .initial, .active:
                guard draggedFavoriteID == nil, let payload = session.draggedItemIDs(for: String.self).first else { return }
                draggedFavoriteID = UUID(uuidString: payload)
            case .ended(let operation):
                if operation == .cancel || operation == .forbidden { finishDrag() }
            case .dataTransferCompleted:
                finishDrag()
            @unknown default:
                finishDrag()
            }
        }
        .onChange(of: pages.count) { _, count in
            pageIndex = min(pageIndex ?? 0, max(count - 1, 0))
        }
    }

    private func page(_ nodes: [SidebarNode], index: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columnCount), spacing: Self.spacing) {
            ForEach(nodes) { node in
                FavoriteTile(model: model, node: node, isDragging: draggedFavoriteID == node.id)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(pagedHeight, Self.tileHeight), alignment: .top)
        .contentShape(Rectangle())
        .animation(Motion.snappy(reduceMotion: reduceMotion), value: nodes.map(\.id))
        .dropDestination(for: String.self) { items, session in
            guard let payload = items.first else { return }
            let container = NodeContainer.favorites(profileID: model.currentSpace.profileID)
            if let sourceID = UUID(uuidString: payload), let targetIndex = previewIDs.firstIndex(of: sourceID),
               let sourceIndex = model.favorites.firstIndex(where: { $0.id == sourceID }) {
                let insertionIndex = SidebarViewMetrics.favoriteDropIndex(sourceIndex: sourceIndex, targetIndex: targetIndex)
                SidebarDrop.handle(items, model: model, container: container, index: insertionIndex)
                finishDrag()
                return
            }
            let innerWidth = model.sidebarWidth - SidebarView.horizontalPadding * 2
            let slot = SidebarViewMetrics.favoriteSlot(at: session.location, availableWidth: innerWidth, columnCount: columnCount)
            guard slot < nodes.count else {
                let insertionIndex = index * columnCount * Self.maximumRows + nodes.count
                SidebarDrop.handle(items, model: model, container: container, index: insertionIndex)
                return
            }
            SidebarDrop.handle(items, model: model, onto: nodes[slot])
        }
        .dropConfiguration { _ in DropConfiguration(operation: .move) }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active:
                isDropTargeted = true
                previewDrop(session, page: index)
            case .exiting:
                isDropTargeted = false
                withAnimation(Motion.snappy(reduceMotion: reduceMotion)) { previewIDs = [] }
            default:
                isDropTargeted = false
            }
        }
    }

    private func previewDrop(_ session: DropSession, page: Int) {
        guard let payload = session.localSession?.draggedItemIDs(for: String.self).first,
              let sourceID = UUID(uuidString: payload), model.favorites.contains(where: { $0.id == sourceID }) else { return }
        draggedFavoriteID = sourceID
        let innerWidth = model.sidebarWidth - SidebarView.horizontalPadding * 2
        let slot = SidebarViewMetrics.favoriteSlot(at: session.location, availableWidth: innerWidth, columnCount: columnCount)
        let targetIndex = page * columnCount * Self.maximumRows + slot
        let ids = previewIDs.isEmpty ? model.favorites.map(\.id) : previewIDs
        let reordered = SidebarViewMetrics.favoriteOrder(ids, moving: sourceID, to: targetIndex)
        guard reordered != previewIDs else { return }
        withAnimation(Motion.snappy(reduceMotion: reduceMotion)) { previewIDs = reordered }
    }

    private func finishDrag() {
        withAnimation(Motion.snappy(reduceMotion: reduceMotion)) {
            previewIDs = []
            draggedFavoriteID = nil
            isDropTargeted = false
        }
    }
}

struct PageDots: View {
    let count: Int
    @Binding var selection: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button { withAnimation(Motion.snappy(reduceMotion: reduceMotion)) { selection = index } } label: {
                    Circle()
                        .fill(Color.primary.opacity((selection ?? 0) == index ? 0.55 : 0.18))
                        .frame(width: 5, height: 5)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Página \(index + 1) de \(count)")
                .dropDestination(for: String.self) { _, _ in false } isTargeted: { isTargeted in
                    guard isTargeted else { return }
                    withAnimation(Motion.snappy(reduceMotion: reduceMotion)) { selection = index }
                }
            }
        }
    }
}

struct FavoriteTile: View {
    @Bindable var model: WindowModel
    let node: SidebarNode
    var isDragging = false
    @ViewState private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var isSelected: Bool { model.currentSpace.selectedNodeID == node.id }

    var body: some View {
        FaviconView(url: node.liveURL ?? node.children.first?.liveURL, size: 18, allowsNetwork: node.allowsFaviconNetwork)
            .frame(maxWidth: .infinity)
            .frame(height: SidebarViewMetrics.favoriteTileHeight)
            .background(
                RoundedRectangle(cornerRadius: SidebarPalette.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? SidebarPalette.selectedTileFill(colorScheme) : SidebarPalette.controlFill(colorScheme, isActive: isHovering))
                    .shadow(color: .black.opacity(isSelected ? 0.1 : 0), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SidebarPalette.rowCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.1 : 0.04), lineWidth: 0.75)
            )
            .contentShape(Rectangle())
            .clickable()
            .onTapGesture { model.select(node) }
            .onHover { isHovering = $0 }
            .help(node.displayTitle)
            .accessibilityLabel(node.displayTitle)
            .accessibilityAddTraits(.isButton)
            .draggable(String.self, id: \.self, item: node.id.uuidString)
            .opacity(isDragging ? 0.35 : 1)
            .contextMenu { NodeContextMenu(model: model, node: node) }
    }
}

struct SidebarFooter: View {
    @Bindable var model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            SidebarProfileMenu(model: model)
            Spacer(minLength: 0)
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(model.spaces.enumerated()), id: \.element.id) { index, space in
                        SpaceDot(model: model, space: space, isSelected: space.id == model.selectedSpaceID) {
                            withAnimation(Motion.spring(reduceMotion: reduceMotion)) { model.switchToSpace(at: index) }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(width: min(CGFloat(model.spaces.count) * 14 + 16, 120), height: 24)
            .background(Capsule().fill(SidebarPalette.glassFill(colorScheme, isActive: false)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
            .popover(isPresented: $model.isThemeEditorPresented, arrowEdge: .top) { ArcThemeEditor(space: model.currentSpace) }
            .popover(isPresented: Binding(get: { model.spaceIconEditingID != nil }, set: { if !$0 { model.spaceIconEditingID = nil } }), arrowEdge: .top) {
                SpaceIconPicker(space: model.currentSpace) { model.spaceIconEditingID = nil }
            }
            Spacer(minLength: 0)
            SidebarCircleButton(symbolName: DownloadManager.shared.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.to.line", label: "Descargas", action: openDownloads)
        }
        .frame(height: SidebarView.headerHeight)
    }

    private func openDownloads() {
        AppDelegate.shared.openDownloadsLibrary(profileID: model.profileID, allowsHistory: !model.isPrivate)
    }
}

struct SidebarProfileMenu: View {
    @Bindable var model: WindowModel
    @Environment(\.colorScheme) private var colorScheme

    private var profile: Profile? { model.store.profile(for: model.currentSpace) }

    var body: some View {
        ParsecDropdown(arrowEdge: .top, entries: entries) {
            Image(systemName: model.isPrivate ? "eyeglasses" : profile?.iconSymbol ?? "person.crop.circle.fill")
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: SidebarView.headerHeight, height: SidebarView.headerHeight)
                .background(Circle().fill(SidebarPalette.glassFill(colorScheme, isActive: false)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.75))
                .contentShape(Circle())
        }
        .help(profile?.name ?? "Perfil")
        .accessibilityLabel("Perfil y opciones")
    }

    private func entries() -> [MenuEntry] {
        let assistantName = model.store.settings.assistantProvider.assistantName
        return [
            .header(profile?.name ?? "Ventana privada"),
            .action("Administrar perfiles", symbol: "person.crop.circle") { AppDelegate.shared.openSettings(section: .profiles) },
            .divider,
            .action("Nueva pestaña", symbol: "plus.square", shortcut: "⌘T") { model.presentCommandBar(mode: .newTab) },
            .action("Nueva vista dividida", symbol: "rectangle.split.2x1", shortcut: "⌃⌘=", isEnabled: !model.isPrivate && model.selectedNode != nil) { model.splitView() },
            .action("Nuevo Space", symbol: "plus.square.on.square", shortcut: "⌥⌘N", isEnabled: !model.isPrivate) { model.isNewSpacePresented = true },
            .action("Nueva carpeta", symbol: "folder.badge.plus", isEnabled: !model.isPrivate) { model.createFolder(in: .pinned(spaceID: model.currentSpace.id)) },
            .divider,
            .action("Preguntar a \(assistantName)", symbol: "sparkle", shortcut: "⌘J") { model.isAssistantPresented.toggle() },
            .action("Configuración", symbol: "gearshape", shortcut: "⌘,") { AppDelegate.shared.openSettings() },
        ]
    }
}

struct SpaceDot: View {
    private static let dotSize: CGFloat = 6

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
                    .fill(Color.primary.opacity(isSelected ? 1 : isHovering ? 0.7 : 0.45))
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .frame(width: 14, height: 24)
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isSelected)
    }
}
