import AppKit
import SwiftUI

struct SidebarNodeRow: View {
    @Bindable var model: WindowModel
    @Bindable var node: SidebarNode
    let depth: Int

    var body: some View {
        switch node.kind {
        case .folder:
            VStack(alignment: .leading, spacing: 1) {
                FolderRow(model: model, node: node, depth: depth)
                if node.isExpanded {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(node.children) { child in
                            SidebarNodeRow(model: model, node: child, depth: depth + 1)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -8)),
                        removal: .opacity.combined(with: .offset(y: -4))
                    ))
                }
            }
            .mask { Rectangle().padding(.vertical, -SidebarDropMetrics.indicatorOverhang) }
        case .tab, .split:
            TabRow(model: model, node: node, depth: depth)
        }
    }
}

enum SidebarDropMetrics {
    static let indicatorOverhang: CGFloat = 6
}

struct RowBackground: View {
    let isSelected: Bool
    let isHovering: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: LayoutConstants.rowCornerRadius, style: .continuous)
            .fill(SidebarPalette.rowFill(colorScheme, isSelected: isSelected, isHovering: isHovering))
            .shadow(color: .black.opacity(isSelected ? 0.09 : 0), radius: 3, y: 1)
    }
}

struct DropIndicator: View {
    private static let knobSize: CGFloat = 8
    private static let lineThickness: CGFloat = 2

    let axis: Axis

    var body: some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: -1)) : AnyLayout(VStackLayout(spacing: -1))
        layout {
            Circle()
                .strokeBorder(Color.primary, lineWidth: Self.lineThickness)
                .frame(width: Self.knobSize, height: Self.knobSize)
            Capsule()
                .fill(Color.primary)
                .frame(width: axis == .vertical ? Self.lineThickness : nil, height: axis == .horizontal ? Self.lineThickness : nil)
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: axis == .horizontal ? .leading : .top)))
    }
}

extension View {
    func dropIndicator(_ isVisible: Bool, axis: Axis = .horizontal, leadingInset: CGFloat = 0) -> some View {
        overlay(alignment: .topLeading) {
            if isVisible {
                DropIndicator(axis: axis)
                    .padding(.leading, axis == .horizontal ? leadingInset : 0)
                    .frame(maxWidth: axis == .horizontal ? .infinity : nil, maxHeight: axis == .vertical ? .infinity : nil, alignment: .topLeading)
                    .offset(x: axis == .vertical ? -5 : 0, y: axis == .horizontal ? -5 : 0)
            }
        }
        .animation(.snappy(duration: 0.15), value: isVisible)
    }
}

struct InlineRenameField: View {
    let initialText: String
    let font: Font
    let onFinish: (String?) -> Void
    @ViewState private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .focused($isFocused)
            .onSubmit { onFinish(text) }
            .onExitCommand { onFinish(nil) }
            .onChange(of: isFocused) { _, isStillFocused in
                if !isStillFocused { onFinish(text) }
            }
            .task {
                text = initialText
                isFocused = true
            }
            .accessibilityLabel("Nuevo nombre")
    }
}

struct TabRow: View {
    @Bindable var model: WindowModel
    @Bindable var node: SidebarNode
    let depth: Int
    @ViewState private var isHovering = false
    @ViewState private var isDropTargeted = false

    private var isSelected: Bool { model.currentSpace.selectedNodeID == node.id }
    private var isLoaded: Bool { node.allTabs.contains { $0.page != nil } }
    private var isCapturing: Bool { node.allTabs.contains { $0.page?.isCapturingMedia == true } }
    private var isToday: Bool { model.isTodayNode(node) }
    private var closesTab: Bool { isToday || isLoaded }
    private var closeSymbol: String { closesTab && !isToday ? "minus" : "xmark" }
    private var closeLabel: String {
        if isToday { return "Cerrar" }
        return isLoaded ? "Cerrar pestaña" : "Quitar de la carpeta"
    }

    private func performCloseAction() {
        guard closesTab else { return BrowserStore.shared.remove(node.id) }
        model.close(node)
    }

    private func selectNode() {
        model.select(node)
    }

    private func beginRenaming() {
        model.renamingNodeID = node.id
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if node.isSplit {
                    SplitRowContent(model: model, split: node, isSelected: isSelected)
                } else {
                    FaviconView(url: node.liveURL, size: 16, allowsNetwork: node.allowsFaviconNetwork)
                    if model.renamingNodeID == node.id {
                        InlineRenameField(initialText: node.displayTitle, font: .system(size: 13, weight: .medium)) { model.finishRenaming(node, with: $0) }
                    } else {
                        Text(node.displayTitle)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 10 + CGFloat(depth) * LayoutConstants.folderIndent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: beginRenaming)
            .onTapGesture(perform: selectNode)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            if isCapturing {
                Circle().fill(Color.red).frame(width: 6, height: 6).accessibilityLabel("Usando cámara o micrófono")
            }
            if isHovering {
                Button(action: performCloseAction) {
                    Image(systemName: closeSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(closeLabel)
                .accessibilityLabel(closeLabel)
            }
        }
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .dropIndicator(isDropTargeted, leadingInset: CGFloat(depth) * LayoutConstants.folderIndent)
        .contentShape(Rectangle())
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .clickable()
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .draggable(node.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            SidebarDrop.handle(items, model: model, onto: node)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu { NodeContextMenu(model: model, node: node) }
    }
}

struct SplitRowContent: View {
    @Bindable var model: WindowModel
    @Bindable var split: SidebarNode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(split.children.enumerated()), id: \.element.id) { index, pane in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 6)
                }
                HStack(spacing: 6) {
                    FaviconView(url: pane.liveURL, size: 15, allowsNetwork: pane.allowsFaviconNetwork)
                    Text(pane.displayTitle.isEmpty ? "Nuevo panel" : pane.displayTitle)
                        .font(.system(size: 13, weight: isSelected && pane.id == model.focusedPaneID ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.select(split)
                    model.focusPane(pane.id)
                }
            }
        }
    }
}

struct FolderRow: View {
    @Bindable var model: WindowModel
    @Bindable var node: SidebarNode
    let depth: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var isHovering = false
    @ViewState private var isDropTargeted = false

    private func toggleExpanded() {
        withAnimation(Motion.disclosure(reduceMotion: reduceMotion)) { node.isExpanded.toggle() }
        BrowserStore.shared.saveSoon()
    }

    private func beginRenaming() {
        model.renamingNodeID = node.id
    }

    var body: some View {
        HStack(spacing: 8) {
            FolderIconView(symbolName: node.iconSymbol, size: SidebarViewMetrics.folderIconSize, weight: .semibold)
            if model.renamingNodeID == node.id {
                InlineRenameField(initialText: node.title, font: .system(size: SidebarViewMetrics.folderTitleSize, weight: .semibold)) { model.finishRenaming(node, with: $0) }
            } else {
                Text(node.title.isEmpty ? "Carpeta" : node.title)
                    .font(.system(size: SidebarViewMetrics.folderTitleSize, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovering {
                ParsecDropdown(arrowEdge: .trailing) {
                    FolderMenu.entries(model: model, node: node)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .hoverHighlight(cornerRadius: 6)
                .help("Opciones de la carpeta")
                .accessibilityLabel("Opciones de la carpeta")
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                .foregroundStyle(.secondary)
                .opacity(isHovering || !node.isExpanded ? 1 : 0)
        }
        .padding(.leading, 10 + CGFloat(depth) * LayoutConstants.folderIndent)
        .padding(.trailing, 8)
        .frame(height: SidebarViewMetrics.folderRowHeight)
        .background(RowBackground(isSelected: false, isHovering: isHovering))
        .overlay(alignment: .bottomLeading) {
            if isDropTargeted {
                DropIndicator(axis: .horizontal)
                    .padding(.leading, CGFloat(depth + 1) * LayoutConstants.folderIndent)
                    .offset(y: 5)
            }
        }
        .animation(.snappy(duration: 0.15), value: isDropTargeted)
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture(count: 2, perform: beginRenaming)
        .onTapGesture(perform: toggleExpanded)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(node.isExpanded ? "Expandida" : "Contraída")
        .draggable(node.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            SidebarDrop.handle(items, model: model, container: .folder(nodeID: node.id), index: nil)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu { NativeMenuItems(entries: FolderMenu.entries(model: model, node: node)) }
        .popover(isPresented: Binding(get: { model.folderIconEditingID == node.id }, set: { if !$0 { model.folderIconEditingID = nil } }), arrowEdge: .trailing) {
            FolderIconPicker(folder: node) { model.folderIconEditingID = nil }
        }
    }
}

struct NodeContextMenu: View {
    @Bindable var model: WindowModel
    let node: SidebarNode

    private var store: BrowserStore { BrowserStore.shared }
    private var isFavorite: Bool { model.favorites.find(node.id) != nil }
    private var isToday: Bool { model.isTodayNode(node) }

    var body: some View {
        if let url = node.liveURL {
            Button { Clipboard.copy(url.absoluteString) } label: { Label("Copiar URL", systemImage: "link") }
        }
        if !model.isPrivate {
            if !isFavorite {
                Button { model.renamingNodeID = node.id } label: { Label("Renombrar", systemImage: "pencil") }
            }
            Divider()
            if isFavorite {
                Button { store.move(node.id, into: .today(spaceID: model.currentSpace.id), at: 0) } label: { Label("Quitar de favoritos", systemImage: "star.slash") }
            } else {
                Button { model.addToFavorites(node) } label: { Label("Añadir a favoritos", systemImage: "star") }
                Button {
                    let destination: NodeContainer = isToday ? .pinned(spaceID: model.currentSpace.id) : .today(spaceID: model.currentSpace.id)
                    store.move(node.id, into: destination, at: isToday ? nil : 0)
                } label: { Label(isToday ? "Fijar" : "Desfijar", systemImage: isToday ? "pin" : "pin.slash") }
            }
            if node.isTab && model.selectedNode?.id != node.id {
                Button { model.addToSplit(node.id) } label: { Label("Dividir con la pestaña actual", systemImage: "rectangle.split.2x1") }
            }
            Menu {
                ForEach(model.spaces.filter { $0.id != model.currentSpace.id }) { space in
                    Button(space.title) { store.move(node.id, into: .today(spaceID: space.id), at: 0) }
                }
            } label: { Label("Mover a Space", systemImage: "square.stack") }
        }
        Divider()
        if node.allTabs.contains(where: { $0.page != nil }) && !isToday {
            Button { store.unloadPages(in: node) } label: { Label("Descargar de memoria", systemImage: "moon.zzz") }
        }
        if isToday || !isFavorite {
            Button(role: .destructive) {
                isToday ? model.close(node) : store.remove(node.id)
            } label: { Label(isToday ? "Cerrar" : "Eliminar", systemImage: isToday ? "xmark" : "trash") }
        } else {
            Button(role: .destructive) { store.remove(node.id) } label: { Label("Eliminar de favoritos", systemImage: "trash") }
        }
    }
}

@MainActor
enum FolderMenu {
    static func entries(model: WindowModel, node: SidebarNode) -> [MenuEntry] {
        let store = BrowserStore.shared
        let folderName = node.title.isEmpty ? "Carpeta" : node.title
        return [
            .action("Compartir carpeta…", symbol: "square.and.arrow.up") { FolderSharing.share(node, from: model.window) },
            .divider,
            .action("Nueva subcarpeta", symbol: "folder.badge.plus") {
                model.createFolder(in: .folder(nodeID: node.id))
                node.isExpanded = true
            },
            .action("Convertir “\(folderName)” en Space", symbol: "square.stack", isEnabled: !model.isPrivate) { model.turnFolderIntoSpace(node) },
            .divider,
            .action("Cambiar icono…", symbol: "face.smiling") { model.folderIconEditingID = node.id },
            .action("Renombrar", symbol: "pencil") { model.renamingNodeID = node.id },
            .action("Duplicar", symbol: "plus.square.on.square") { model.duplicateFolder(node) },
            .submenu("Mover a", symbol: "arrow.right.square", entries: model.spaces.filter { $0.id != model.currentSpace.id }.map { space in
                .action(space.title, symbol: space.iconSymbol ?? "circle.fill") { store.move(node.id, into: .pinned(spaceID: space.id)) }
            }),
            .divider,
            .action("Eliminar", symbol: "trash", isDestructive: true) { FolderActions.deleteWithContents(node) },
        ]
    }
}

@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
enum FolderActions {
    static func deleteWithContents(_ folder: SidebarNode) {
        let alert = NSAlert()
        alert.messageText = "¿Eliminar \(folder.title.isEmpty ? "la carpeta" : folder.title) y sus \(folder.allTabs.count) pestañas?"
        alert.informativeText = "Puedes reabrir las últimas con ⇧⌘T."
        alert.addButton(withTitle: "Eliminar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        BrowserStore.shared.remove(folder.id)
    }
}

@MainActor
enum FolderRemoval {
    static func dissolve(_ folder: SidebarNode) {
        let store = BrowserStore.shared
        guard let container = store.container(of: folder.id), let index = store.index(of: folder.id, in: container) else { return }
        let children = folder.children
        store.detach(folder.id)
        for (offset, child) in children.enumerated() {
            store.insert(child, into: container, at: index + offset)
        }
    }
}

@MainActor
enum SidebarDrop {
    @discardableResult
    static func handle(_ items: [String], model: WindowModel, onto target: SidebarNode) -> Bool {
        let store = BrowserStore.shared
        guard let container = store.container(of: target.id) ?? todayContainer(of: target, model: model) else { return false }
        let targetIndex = store.index(of: target.id, in: container) ?? model.currentSpace.today.firstIndex { $0.id == target.id }
        return handle(items, model: model, container: container, index: targetIndex)
    }

    @discardableResult
    static func handle(_ items: [String], model: WindowModel, container: NodeContainer, index: Int?) -> Bool {
        guard !model.isPrivate, let payload = items.first else { return false }
        let store = BrowserStore.shared
        if let nodeID = UUID(uuidString: payload) {
            let sourceContainer = store.container(of: nodeID)
            let sourceIndex = sourceContainer.flatMap { store.index(of: nodeID, in: $0) }
            let adjustedIndex = sourceContainer == container && (sourceIndex ?? Int.max) < (index ?? 0) ? index.map { $0 - 1 } : index
            store.move(nodeID, into: container, at: adjustedIndex)
            return true
        }
        guard let url = URL(string: payload), url.scheme != nil else { return false }
        store.insert(.tab(url: url, title: url.host() ?? ""), into: container, at: index)
        return true
    }

    private static func todayContainer(of node: SidebarNode, model: WindowModel) -> NodeContainer? {
        model.isTodayNode(node) ? .today(spaceID: model.currentSpace.id) : nil
    }
}
