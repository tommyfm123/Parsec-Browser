import AppKit
import SwiftUI

struct FolderIconView: View {
    let symbolName: String?
    var size: CGFloat = 16
    var weight = Font.Weight.medium
    var isFilled = false
    var tint: Color? = nil

    private var iconTint: Color {
        if let tint { return tint }
        return isFilled ? SwatchPalette.defaultIcon.color : Color.primary
    }

    var body: some View {
        Image(systemName: symbolName ?? (isFilled ? "folder.fill" : "folder"))
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(iconTint)
            .frame(width: size + 4, height: size + 2)
            .accessibilityHidden(true)
    }
}

struct SymbolPicker: View {
    static let symbols = [
        "bolt.fill", "asterisk", "bookmark.fill", "archivebox.fill", "lightbulb.fill", "cloud.fill",
        "chevron.left.forwardslash.chevron.right", "hammer.fill", "video.fill", "music.note", "person.2.fill", "star.fill",
        "heart.fill", "flag.fill", "briefcase.fill", "cart.fill", "creditcard.fill", "house.fill",
        "graduationcap.fill", "book.fill", "paintbrush.fill", "camera.fill", "gamecontroller.fill", "airplane",
        "leaf.fill", "flame.fill", "globe", "sparkles", "doc.text.fill", "chart.bar.fill",
        "wrench.and.screwdriver.fill", "cpu", "link", "lock.fill", "tag.fill", "gift.fill",
    ]
    private static let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6)

    let title: String
    let selectedSymbol: String?
    let preview: AnyView
    var selectedColor: ThemeColor? = nil
    var onColorSelect: ((ThemeColor?) -> Void)? = nil
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                preview
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Sin icono") { onSelect(nil) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .disabled(selectedSymbol == nil)
            }
            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button { onSelect(symbol) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(symbolTint)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Color.primary.opacity(selectedSymbol == symbol ? 0.14 : 0.04)))
                            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Color.accentColor.opacity(selectedSymbol == symbol ? 0.8 : 0), lineWidth: 1.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
            if let onColorSelect {
                Divider()
                ColorPalettePicker(title: "Todos los iconos", selection: selectedColor ?? SwatchPalette.defaultIcon, onSelect: onColorSelect)
            }
        }
        .padding(14)
        .frame(width: onColorSelect == nil ? nil : 300)
    }

    private var symbolTint: Color {
        guard onColorSelect != nil else { return .primary }
        return selectedColor?.color ?? SwatchPalette.defaultIcon.color
    }
}

struct FolderIconPicker: View {
    @Bindable var folder: SidebarNode
    let onDone: () -> Void

    var body: some View {
        SymbolPicker(
            title: folder.title.isEmpty ? "Carpeta" : folder.title,
            selectedSymbol: folder.iconSymbol,
            preview: AnyView(FolderIconView(symbolName: folder.iconSymbol, size: 22, isFilled: true, tint: BrowserStore.shared.settings.folderIconColor?.color)),
            selectedColor: BrowserStore.shared.settings.folderIconColor,
            onColorSelect: { color in
                BrowserStore.shared.settings.folderIconColor = color
                BrowserStore.shared.saveSoon()
            },
            onSelect: { symbol in
                folder.iconSymbol = symbol
                BrowserStore.shared.saveSoon()
                onDone()
            }
        )
    }
}

struct SpaceIconPicker: View {
    @Bindable var space: Space
    let onDone: () -> Void

    var body: some View {
        SymbolPicker(
            title: space.title,
            selectedSymbol: space.iconSymbol,
            preview: AnyView(Image(systemName: space.iconSymbol ?? "circle.fill").font(.system(size: 16)))
        ) { symbol in
            space.iconSymbol = symbol
            BrowserStore.shared.saveSoon()
            onDone()
        }
    }
}

@MainActor
enum FolderSharing {
    static func share(_ folder: SidebarNode, from window: NSWindow?) {
        let lines = folder.allTabs.compactMap { tab in tab.url.map { "\(tab.displayTitle) — \($0.absoluteString)" } }
        SharingPresenter.share(([folder.title] + lines).joined(separator: "\n"), from: window)
    }
}
