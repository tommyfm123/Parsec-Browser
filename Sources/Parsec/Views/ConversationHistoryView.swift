import SwiftUI

enum HistoryPeriod: CaseIterable {
    case today
    case yesterday
    case lastWeek
    case older

    var title: String {
        switch self {
        case .today: "Hoy"
        case .yesterday: "Ayer"
        case .lastWeek: "Últimos 7 días"
        case .older: "Anteriores"
        }
    }

    private static let weekLength = 7

    static func period(for date: Date, calendar: Calendar = .current) -> HistoryPeriod {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? Int.max
        return days < weekLength ? .lastWeek : .older
    }
}

struct ConversationHistoryView: View {
    private static let panelSize = CGSize(width: 640, height: 540)
    private static let radius: CGFloat = 24

    @Bindable var model: WindowModel
    @ViewState private var query = ""
    @FocusState private var isSearchFocused: Bool
    private var store: ConversationStore { ConversationStore.shared }

    private var sections: [(period: HistoryPeriod, conversations: [StoredConversation])] {
        let matches = store.list(profileID: model.profileID, matching: query.trimmingCharacters(in: .whitespaces))
        let grouped = Dictionary(grouping: matches) { HistoryPeriod.period(for: $0.updatedAt) }
        return HistoryPeriod.allCases.compactMap { period in grouped[period].map { (period, $0) } }
    }

    var body: some View {
        ZStack {
            ZStack {
                VisualEffectBackground(material: .fullScreenUI, blendingMode: .withinWindow)
                Color.black.opacity(0.12)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.isHistoryPresented = false }
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                content
            }
            .frame(width: Self.panelSize.width, height: Self.panelSize.height)
            .liquidGlass(in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.3), radius: 50, y: 20)
        }
        .onAppear { isSearchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Buscar en tus conversaciones", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isSearchFocused)
                .onExitCommand { model.isHistoryPresented = false }
            IconButton(symbolName: "xmark", label: "Cerrar (Esc)") { model.isHistoryPresented = false }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    @ViewBuilder
    private var content: some View {
        if sections.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(query.isEmpty ? "Todavía no tienes conversaciones" : "Nada coincide con “\(query)”")
                    .font(.system(size: 14, weight: .medium))
                Text(query.isEmpty ? "Lo que le preguntes a la IA aparecerá aquí." : "Prueba con otras palabras.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sections, id: \.period) { section in
                        DropdownHeader(title: section.period.title)
                        ForEach(section.conversations) { conversation in
                            ConversationHistoryRow(conversation: conversation) {
                                model.openConversation(conversation.id)
                            } onDelete: {
                                withAnimation(.snappy) { store.delete(conversation.id) }
                            }
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
        }
    }
}

struct ConversationHistoryRow: View {
    let conversation: StoredConversation
    let onOpen: () -> Void
    let onDelete: () -> Void
    @ViewState private var isHovering = false

    private var isBrowsing: Bool { conversation.messages.contains(where: \.isBrowsing) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isBrowsing ? "cursorarrow.motionlines" : "sparkle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                if !conversation.preview.isEmpty {
                    Text(conversation.preview).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isHovering {
                IconButton(symbolName: "trash", label: "Borrar conversación", action: onDelete)
                    .foregroundStyle(.secondary)
            } else {
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(isHovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
