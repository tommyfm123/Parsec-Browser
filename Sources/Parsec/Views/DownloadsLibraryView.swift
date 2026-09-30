import AppKit
import SwiftUI

enum DownloadsLibrarySection: String, CaseIterable, Identifiable {
    case downloads = "Descargas"
    case history = "Historial"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .downloads: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

enum LibraryDateFilter: String, CaseIterable, Identifiable {
    case all = "Todas"
    case today = "Hoy"
    case lastSevenDays = "Últimos 7 días"
    case lastThirtyDays = "Últimos 30 días"

    var id: String { rawValue }

    func includes(_ date: Date, relativeTo now: Date = .now) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .lastSevenDays:
            return date >= (calendar.date(byAdding: .day, value: -7, to: now) ?? now)
        case .lastThirtyDays:
            return date >= (calendar.date(byAdding: .day, value: -30, to: now) ?? now)
        }
    }
}

struct DownloadsLibraryView: View {
    static let size = CGSize(width: 920, height: 660)
    private static let sidebarWidth: CGFloat = 232
    private static let panelInset: CGFloat = 8

    @Bindable var manager: DownloadManager
    let profileID: UUID
    let allowsHistory: Bool
    @ViewState private var selection: DownloadsLibrarySection
    @ViewState private var searchText = ""
    @ViewState private var dateFilter = LibraryDateFilter.all
    @ViewState private var historyEntries: [HistoryEntry] = []
    @ViewState private var itemToDelete: DownloadItem?
    @ViewState private var isClearConfirmationPresented = false
    @ViewState private var deleteError: String?

    init(initialSection: DownloadsLibrarySection, profileID: UUID, allowsHistory: Bool) {
        self.profileID = profileID
        self.allowsHistory = allowsHistory
        _selection = ViewState(initialValue: initialSection == .history && !allowsHistory ? .downloads : initialSection)
        _manager = Bindable(wrappedValue: DownloadManager.shared)
    }

    private var filteredDownloads: [DownloadItem] {
        manager.items.filter { item in
            dateFilter.includes(item.createdAt) && (searchText.isEmpty || item.filename.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var filteredHistory: [HistoryEntry] {
        historyEntries.filter { entry in
            dateFilter.includes(entry.lastVisited) && (searchText.isEmpty || entry.title.localizedCaseInsensitiveContains(searchText) || entry.url.absoluteString.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var downloadGroups: [(title: String, items: [DownloadItem])] {
        groupItems(filteredDownloads, date: \.createdAt)
    }

    private var historyGroups: [(title: String, items: [HistoryEntry])] {
        groupItems(filteredHistory, date: \.lastVisited)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            panel
                .padding(Self.panelInset)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            VisualEffectBackground(material: .hudWindow)
                .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.88))
        }
        .ignoresSafeArea()
        .task { refreshHistory() }
        .confirmationDialog("¿Eliminar esta descarga?", item: $itemToDelete) { item in
            Button("Eliminar archivo y registro", role: .destructive) { delete(item) }
            Button("Cancelar", role: .cancel) {}
        } message: { item in
            Text("Se eliminará \(item.filename) de la carpeta de descargas.")
        }
        .confirmationDialog("¿Limpiar las descargas terminadas?", isPresented: $isClearConfirmationPresented) {
            Button("Limpiar lista", role: .destructive) { manager.clearFinished() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los archivos descargados seguirán en tu Mac.")
        }
        .alert("No se pudo eliminar la descarga", isPresented: deleteErrorPresented) {
            Button("Aceptar", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "Inténtalo de nuevo.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Biblioteca", systemImage: "books.vertical")
                .font(.system(size: 17, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.top, 46)
            Divider().padding(.horizontal, 10)
            VStack(spacing: 2) {
                ForEach(DownloadsLibrarySection.allCases) { section in
                    DownloadsLibrarySidebarRow(
                        section: section,
                        isSelected: selection == section,
                        isEnabled: section != .history || allowsHistory,
                        count: section == .downloads ? manager.items.count : nil,
                        action: { selection = section }
                    )
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WindowDragArea())
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(selection.rawValue, systemImage: selection.symbolName)
                    .font(.system(size: 17, weight: .medium))
                Spacer()
                if selection == .downloads {
                    Button("Limpiar") { isClearConfirmationPresented = true }
                        .buttonStyle(.borderless)
                        .disabled(!manager.items.contains { $0.state != .inProgress })
                } else {
                    Button("Actualizar", systemImage: "arrow.clockwise", action: refreshHistory)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 16)
            toolbar
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if selection == .downloads {
                        downloadContent
                    } else {
                        historyContent
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(selection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.window, style: .continuous).fill(Color.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Radius.window, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(selection == .downloads ? "Buscar descargas" : "Buscar en el historial", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.09)))
            Menu {
                Picker("Fecha", selection: $dateFilter) {
                    ForEach(LibraryDateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            } label: {
                Label(dateFilter.rawValue, systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private var downloadContent: some View {
        if filteredDownloads.isEmpty {
            LibraryEmptyState(
                symbolName: searchText.isEmpty ? "arrow.down.doc" : "magnifyingglass",
                title: searchText.isEmpty ? "Todavía no hay descargas" : "No hay resultados",
                detail: searchText.isEmpty ? "Las descargas que hagas van a aparecer acá." : "Probá con otro nombre o cambiá el filtro de fecha."
            )
        } else {
            ForEach(downloadGroups.indices, id: \.self) { groupIndex in
                let group = downloadGroups[groupIndex]
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    VStack(spacing: 0) {
                        ForEach(group.items) { item in
                            DownloadLibraryRow(item: item, onOpen: { manager.open(item) }, onReveal: { manager.reveal(item) }, onDelete: { itemToDelete = item })
                            if item.id != group.items.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.09)))
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if filteredHistory.isEmpty {
            LibraryEmptyState(
                symbolName: searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                title: searchText.isEmpty ? "Todavía no hay historial" : "No hay resultados",
                detail: searchText.isEmpty ? "Las páginas que visites van a aparecer acá." : "Probá con otro título o dirección."
            )
        } else {
            ForEach(historyGroups.indices, id: \.self) { groupIndex in
                let group = historyGroups[groupIndex]
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    VStack(spacing: 0) {
                        ForEach(group.items, id: \.url) { entry in
                            HistoryLibraryRow(entry: entry, action: { AppDelegate.shared.openInMainWindow(entry.url) })
                            if entry.url != group.items.last?.url { Divider().padding(.leading, 48) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.09)))
                }
            }
        }
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private func groupItems<Item>(_ items: [Item], date: KeyPath<Item, Date>) -> [(title: String, items: [Item])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0[keyPath: date]) }
        return groups.keys.sorted(by: >).compactMap { day in
            guard let groupedItems = groups[day] else { return nil }
            return (dateTitle(day), groupedItems)
        }
    }

    private func dateTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hoy" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: .now), calendar.isDate(date, inSameDayAs: yesterday) { return "Ayer" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    private func delete(_ item: DownloadItem) {
        do {
            try manager.delete(item)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func refreshHistory() {
        guard allowsHistory else { return }
        historyEntries = BrowserStore.shared.history.allVisits(profileID: profileID)
    }

}

struct DownloadsLibrarySidebarRow: View {
    let section: DownloadsLibrarySection
    let isSelected: Bool
    let isEnabled: Bool
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(section.rawValue).font(.system(size: 13))
                Spacer()
                if let count, count > 0 {
                    Text(count.formatted())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Color.primary.opacity(isSelected ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DownloadLibraryRow: View {
    let item: DownloadItem
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    private var status: String {
        switch item.state {
        case .inProgress: "Descargando · \(Int(item.fractionCompleted * 100))%"
        case .finished: item.createdAt.formatted(.dateTime.hour().minute())
        case .failed: "Descarga interrumpida"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(iconColor.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.state == .inProgress {
                    ProgressView(value: item.fractionCompleted).controlSize(.small)
                } else {
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if item.state == .finished {
                IconButton(symbolName: "arrow.up.right.square", label: "Abrir archivo", action: onOpen)
                IconButton(symbolName: "folder", label: "Mostrar en Finder", action: onReveal)
            }
            if item.state != .inProgress {
                IconButton(symbolName: "trash", label: "Eliminar descarga", action: onDelete)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if item.state == .finished { onOpen() } }
    }

    private var symbolName: String {
        switch item.state {
        case .inProgress: "arrow.down"
        case .finished: "doc.fill"
        case .failed: "exclamationmark"
        }
    }

    private var iconColor: Color {
        switch item.state {
        case .inProgress: .blue
        case .finished: .secondary
        case .failed: .red
        }
    }
}

struct HistoryLibraryRow: View {
    let entry: HistoryEntry
    let action: () -> Void

    private var displayTitle: String { entry.title.isEmpty ? entry.url.host() ?? entry.url.absoluteString : entry.title }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.secondary.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.url.host() ?? entry.url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.lastVisited.formatted(.dateTime.hour().minute()))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            IconButton(symbolName: "arrow.up.right.square", label: "Abrir página", action: action)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: action)
    }
}

struct LibraryEmptyState: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 15, weight: .medium))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }
}
