import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    static let outerInset = SidebarViewMetrics.outerInset
    static let headerTopPadding: CGFloat = 8
    static let headerHeight: CGFloat = 30
    static let horizontalPadding: CGFloat = 8
    static let trafficLightsCenterY = headerTopPadding + headerHeight / 2

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
        .padding(.top, Self.headerTopPadding)
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
                        let proposedWidth = (startWidth + value.translation.width).rounded()
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

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: SidebarView.headerHeight, height: SidebarView.headerHeight)
                .liquidGlass(in: Circle(), isActive: isHovering, interactive: true, showsBorder: true)
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
    var height: CGFloat = 32
    var alwaysShowsFullURL = false
    @ViewState private var isHovering = false

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
                        .matchingPopoverAppearance()
                }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .liquidGlass(in: Capsule(), isActive: isHovering, interactive: true, showsBorder: true)
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture { model.presentCommandBar(mode: .navigateCurrent) }
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Dirección: \(displayText)")
    }
}

enum SidebarPalette {
    static let rowHeight: CGFloat = 38
    static let rowCornerRadius: CGFloat = 10
    static let selectedShadowOpacity = 0.12
    static let favoriteSelectionBorderOpacity = 0.6
    static let neutralSelectionBorderOpacity = 0.22
    static let primaryTextOpacity = 0.88
    static let tertiaryTextOpacity = 0.45

    static func controlFill(_ colorScheme: ColorScheme, isActive: Bool) -> Color {
        colorScheme == .dark ? Color.white.opacity(isActive ? 0.12 : 0.07) : Color.black.opacity(isActive ? 0.08 : 0.05)
    }

    static func rowFill(_ colorScheme: ColorScheme, isSelected: Bool, isHovering: Bool) -> Color {
        let darkOpacity = isSelected ? 0.17 : isHovering ? 0.08 : 0
        let lightOpacity = isSelected ? 0.92 : isHovering ? 0.4 : 0
        return colorScheme == .dark ? Color.white.opacity(darkOpacity) : Color.white.opacity(lightOpacity)
    }
}

struct FavoritesGrid: View {
    private static let spacing = SidebarViewMetrics.favoriteSpacing
    private static let pageEdgeWidth: CGFloat = 18
    private static let pageAnimationDuration = 0.14

    @Bindable var model: WindowModel
    @ViewState private var isDropTargeted = false
    @ViewState private var pageIndex = 0
    @ViewState private var dragOffset: CGFloat = 0
    @ViewState private var pageTurnDirection: Int?
    @ViewState private var draggedFavoriteID: UUID?
    @ViewState private var previewIDs: [UUID] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayedFavorites: [SidebarNode] {
        guard !previewIDs.isEmpty else { return model.favorites }
        let nodes = Dictionary(uniqueKeysWithValues: model.favorites.map { ($0.id, $0) })
        return previewIDs.compactMap { nodes[$0] }
    }

    private var pageSize: Int { SidebarViewMetrics.favoritesPerPage }
    private var pageCount: Int { max((model.favorites.count + pageSize - 1) / pageSize, 1) }
    private var pageAnimation: Animation { .easeOut(duration: reduceMotion ? 0 : Self.pageAnimationDuration) }

    private var pagedHeight: CGFloat {
        let columns = SidebarViewMetrics.favoriteColumns
        let tileHeight = SidebarViewMetrics.favoriteTileHeight
        let rows = CGFloat((min(model.favorites.count, pageSize) + columns - 1) / columns)
        return max(rows * tileHeight + max(rows - 1, 0) * Self.spacing, tileHeight)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                GlassEffectContainer(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(displayedFavorites.enumerated()), id: \.element.id) { index, node in
                            if isTileRendered(index: index) {
                                FavoriteTile(model: model, node: node, isDragging: draggedFavoriteID == node.id) { draggedFavoriteID = node.id }
                                    .frame(width: SidebarViewMetrics.favoriteTileWidth(availableWidth: width), height: SidebarViewMetrics.favoriteTileHeight)
                                    .offset(tileOffset(index: index, width: width))
                                    .allowsHitTesting(index / pageSize == pageIndex)
                            }
                        }
                    }
                }
                .frame(width: width * CGFloat(pageCount), height: pagedHeight, alignment: .topLeading)
                .animation(Motion.snappy(reduceMotion: reduceMotion), value: displayedFavorites.map(\.id))
                .offset(x: -CGFloat(pageIndex) * width + dragOffset)
                .animation(pageAnimation, value: pageIndex)
                .frame(width: width, height: pagedHeight, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .background {
                    if pageCount > 1 {
                        SwipeMonitor(onChange: { trackSwipe($0, width: width) }, onEnd: { finishSwipe($0, width: width) })
                    }
                }
                .dropDestination(for: String.self) { items, session in
                    SidebarDrop.handleFavorite(items, model: model, location: session.location, pageIndex: pageIndex, availableWidth: width)
                    finishDrag()
                }
                .dropConfiguration { _ in DropConfiguration(operation: .move) }
                .onDropSessionUpdated { session in
                    switch session.phase {
                    case .entering, .active:
                        isDropTargeted = true
                        turnPage(at: session.location, width: width)
                        previewDrop(at: session.location, width: width)
                    default:
                        isDropTargeted = false
                    }
                }
            }
            .frame(height: pagedHeight)
            if pageCount > 1 {
                PageDots(count: pageCount, selection: $pageIndex, animation: pageAnimation)
            }
        }
        .overlay {
            if model.favorites.isEmpty {
                Text("Arrastra aquí tus favoritos")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous).strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.6 : 0), lineWidth: 1.5))
        .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: true, allowMove: true), operationsOutsideApp: .init(allowCopy: false)))
        .onDragSessionUpdated { session in
            switch session.phase {
            case .ended(let operation):
                if operation == .cancel || operation == .forbidden { finishDrag() }
            case .dataTransferCompleted:
                finishDrag()
            default:
                break
            }
        }
        .onChange(of: pageCount) { _, count in
            pageIndex = min(pageIndex, count - 1)
            dragOffset = 0
        }
    }

    private func isTileRendered(index: Int) -> Bool {
        index / pageSize == pageIndex || dragOffset != 0 || draggedFavoriteID != nil
    }

    private func tileOffset(index: Int, width: CGFloat) -> CGSize {
        let position = SidebarViewMetrics.favoritePosition(index: index, availableWidth: width)
        return CGSize(width: position.x, height: position.y)
    }

    private func previewDrop(at location: CGPoint, width: CGFloat) {
        guard let sourceID = draggedFavoriteID, model.favorites.contains(where: { $0.id == sourceID }) else { return }
        let slot = SidebarViewMetrics.favoriteSlot(at: location, availableWidth: width)
        let targetIndex = pageIndex * pageSize + slot
        let ids = previewIDs.isEmpty ? model.favorites.map(\.id) : previewIDs
        let reordered = SidebarViewMetrics.favoriteOrder(ids, moving: sourceID, to: targetIndex)
        guard reordered != previewIDs else { return }
        withAnimation(Motion.snappy(reduceMotion: reduceMotion)) { previewIDs = reordered }
    }

    private func turnPage(at location: CGPoint, width: CGFloat) {
        guard draggedFavoriteID != nil else { return }
        let direction = location.x < Self.pageEdgeWidth ? -1 : location.x > width - Self.pageEdgeWidth ? 1 : 0
        guard direction != 0 else { return pageTurnDirection = nil }
        guard pageTurnDirection != direction else { return }
        pageTurnDirection = direction
        pageIndex = min(max(pageIndex + direction, 0), pageCount - 1)
    }

    private func trackSwipe(_ offset: CGFloat, width: CGFloat) {
        guard draggedFavoriteID == nil else { return }
        let isAtEdge = (pageIndex == 0 && offset > 0) || (pageIndex == pageCount - 1 && offset < 0)
        dragOffset = isAtEdge ? offset / 4 : offset
    }

    private func finishSwipe(_ offset: CGFloat, width: CGFloat) {
        guard draggedFavoriteID == nil else { return }
        withAnimation(pageAnimation) {
            dragOffset = 0
            guard abs(offset) > width * LayoutConstants.swipeCommitThreshold else { return }
            pageIndex = min(max(pageIndex + (offset < 0 ? 1 : -1), 0), pageCount - 1)
        }
    }

    private func finishDrag() {
        withAnimation(Motion.snappy(reduceMotion: reduceMotion)) {
            previewIDs = []
            draggedFavoriteID = nil
            pageTurnDirection = nil
            isDropTargeted = false
            dragOffset = 0
        }
    }
}

struct PageDots: View {
    let count: Int
    @Binding var selection: Int
    let animation: Animation

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button { withAnimation(animation) { selection = index } } label: {
                    Circle()
                        .fill(Color.primary.opacity(selection == index ? 0.55 : 0.18))
                        .frame(width: 5, height: 5)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Página \(index + 1) de \(count)")
                .dropDestination(for: String.self) { _, _ in false } isTargeted: { isTargeted in
                    guard isTargeted else { return }
                    withAnimation(animation) { selection = index }
                }
            }
        }
    }
}

struct FavoriteTile: View {
    @Bindable var model: WindowModel
    let node: SidebarNode
    var isDragging = false
    let beginDrag: () -> Void
    @ViewState private var isHovering = false

    private var isSelected: Bool { model.currentSpace.selectedNodeID == node.id }
    private var faviconURL: URL? { node.liveURL ?? node.children.first?.liveURL }
    private var tileShape: RoundedRectangle { RoundedRectangle(cornerRadius: SidebarViewMetrics.favoriteCornerRadius, style: .continuous) }

    private var selectionBorderColor: Color {
        let favicon = FaviconStore.shared.icon(for: faviconURL, allowsNetwork: node.allowsFaviconNetwork)
        let accent = favicon.flatMap(FaviconTone.accentColor)
        return accent?.opacity(SidebarPalette.favoriteSelectionBorderOpacity) ?? Color.primary.opacity(SidebarPalette.neutralSelectionBorderOpacity)
    }

    var body: some View {
        FaviconView(url: faviconURL, size: SidebarViewMetrics.favoriteIconSize, allowsNetwork: node.allowsFaviconNetwork)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                tileShape
                    .strokeBorder(selectionBorderColor, lineWidth: SidebarViewMetrics.favoriteSelectionBorderWidth)
                    .opacity(isSelected ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
            }
            .liquidGlass(in: tileShape, isActive: isSelected || isHovering, interactive: true)
            .shadow(color: .black.opacity(isSelected ? SidebarPalette.selectedShadowOpacity : 0), radius: 2, y: 1)
            .contentShape(Rectangle())
            .clickable()
            .onTapGesture { model.select(node) }
            .onHover { isHovering = $0 }
            .help(node.displayTitle)
            .accessibilityLabel(node.displayTitle)
            .accessibilityAddTraits(.isButton)
            .onDrag {
                beginDrag()
                return NSItemProvider(object: node.id.uuidString as NSString)
            }
            .opacity(isDragging ? 0.35 : 1)
            .contextMenu { NodeContextMenu(model: model, node: node) }
    }
}

struct SidebarFooter: View {
    @Bindable var model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .liquidGlass(in: Capsule(), showsBorder: true)
            .popover(isPresented: $model.isThemeEditorPresented, arrowEdge: .top) { ArcThemeEditor(space: model.currentSpace).matchingPopoverAppearance() }
            .popover(isPresented: Binding(get: { model.spaceIconEditingID != nil }, set: { if !$0 { model.spaceIconEditingID = nil } }), arrowEdge: .top) {
                SpaceIconPicker(space: model.currentSpace) { model.spaceIconEditingID = nil }
                    .matchingPopoverAppearance()
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

    private var profile: Profile? { model.store.profile(for: model.currentSpace) }

    var body: some View {
        ParsecDropdown(arrowEdge: .top, entries: entries) {
            Image(systemName: model.isPrivate ? "eyeglasses" : profile?.iconSymbol ?? "person.crop.circle.fill")
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: SidebarView.headerHeight, height: SidebarView.headerHeight)
                .liquidGlass(in: Circle(), interactive: true, showsBorder: true)
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
