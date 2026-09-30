import SwiftUI

@MainActor
struct MenuEntry: Identifiable {
    enum Kind {
        case action(@MainActor () -> Void)
        case header
        case divider
        case submenu([MenuEntry])
    }

    let id = UUID()
    let kind: Kind
    var title = ""
    var symbolName: String?
    var iconURL: URL?
    var detail: String?
    var shortcut: String?
    var isSelected = false
    var isEnabled = true
    var isDestructive = false
    var keepsOpen = false

    static func action(
        _ title: String, symbol: String? = nil, iconURL: URL? = nil, detail: String? = nil, shortcut: String? = nil,
        isSelected: Bool = false, isEnabled: Bool = true, isDestructive: Bool = false, keepsOpen: Bool = false,
        perform: @escaping @MainActor () -> Void
    ) -> MenuEntry {
        MenuEntry(
            kind: .action(perform), title: title, symbolName: symbol, iconURL: iconURL, detail: detail, shortcut: shortcut,
            isSelected: isSelected, isEnabled: isEnabled, isDestructive: isDestructive, keepsOpen: keepsOpen
        )
    }

    static func header(_ title: String) -> MenuEntry {
        MenuEntry(kind: .header, title: title)
    }

    static var divider: MenuEntry {
        MenuEntry(kind: .divider)
    }

    static func submenu(_ title: String, symbol: String? = nil, entries: [MenuEntry]) -> MenuEntry {
        MenuEntry(kind: .submenu(entries), title: title, symbolName: symbol)
    }
}

struct NativeMenuItems: View {
    let entries: [MenuEntry]

    var body: some View {
        ForEach(entries) { entry in
            switch entry.kind {
            case .action(let perform):
                Button(role: entry.isDestructive ? .destructive : nil, action: perform) { NativeMenuLabel(entry: entry) }
                    .disabled(!entry.isEnabled)
            case .header:
                Text(entry.title)
            case .divider:
                Divider()
            case .submenu(let children):
                Menu { NativeMenuItems(entries: children) } label: { NativeMenuLabel(entry: entry) }
            }
        }
    }
}

struct NativeMenuLabel: View {
    let entry: MenuEntry

    var body: some View {
        if entry.isSelected {
            Label(entry.title, systemImage: "checkmark")
        } else if let symbolName = entry.symbolName {
            Label(entry.title, systemImage: symbolName)
        } else {
            Text(entry.title)
        }
    }
}

struct DropdownList: View {
    private static let maximumHeight: CGFloat = 480

    let entries: () -> [MenuEntry]
    let width: CGFloat
    let onDismiss: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }.scrollIndicators(.never)
        }
        .frame(width: width)
        .frame(maxHeight: Self.maximumHeight)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 1) {
            DropdownEntries(entries: entries(), onDismiss: onDismiss)
        }
        .padding(6)
    }
}

struct DropdownEntries: View {
    let entries: [MenuEntry]
    let onDismiss: () -> Void

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            switch entry.kind {
            case .action(let perform):
                DropdownRow(entry: entry) {
                    perform()
                    if !entry.keepsOpen { onDismiss() }
                }
            case .header:
                DropdownHeader(title: entry.title)
            case .divider:
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
            case .submenu(let children):
                DropdownHeader(title: entry.title)
                DropdownEntries(entries: children, onDismiss: onDismiss)
            }
        }
    }
}

struct DropdownHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 3)
    }
}

struct DropdownRow: View {
    let entry: MenuEntry
    let action: () -> Void

    private var tint: Color { entry.isDestructive ? .red : .primary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: entry.isSelected ? .medium : .regular))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    if let detail = entry.detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 10)
                if let shortcut = entry.shortcut {
                    Text(shortcut).font(.system(size: 11.5, design: .rounded)).foregroundStyle(.tertiary)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(entry.isSelected ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .padding(.vertical, entry.detail == nil ? 0 : 3)
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: 8)
        }
        .buttonStyle(.plain)
        .disabled(!entry.isEnabled)
        .opacity(entry.isEnabled ? 1 : 0.6)
        .accessibilityAddTraits(entry.isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var icon: some View {
        if let iconURL = entry.iconURL {
            FaviconView(url: iconURL, size: 15).frame(width: 18)
        } else if let symbolName = entry.symbolName {
            Image(systemName: symbolName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(entry.isDestructive ? Color.red : Color.secondary)
                .frame(width: 18)
        }
    }
}

struct ParsecDropdown<Label: View>: View {
    var width: CGFloat = 250
    var arrowEdge: Edge = .bottom
    let entries: () -> [MenuEntry]
    @ViewBuilder let label: Label
    @ViewState private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: { label }
            .buttonStyle(.plain)
            .clickable()
            .fixedSize()
            .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
                DropdownList(entries: entries, width: width) { isPresented = false }
            }
    }
}

struct DropdownIconLabel: View {
    let symbolName: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: 7)
    }
}

struct ParsecSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var width: CGFloat = 150

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        ParsecDropdown(width: max(width, 180)) {
            options.map { option in
                MenuEntry.action(option.title, isSelected: option.value == selection) { selection = option.value }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentTitle).font(.system(size: 12.5)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .accessibilityValue(currentTitle)
    }
}

struct ParsecSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = option.value } } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear).shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 2, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .clickable()
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
