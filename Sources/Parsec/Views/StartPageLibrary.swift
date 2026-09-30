import SwiftUI

enum StartPageLibraryTab: String, CaseIterable, Identifiable {
    case chats = "Chats"
    case routines = "Rutinas"

    var id: String { rawValue }
}

enum LibraryMetrics {
    static let spacing: CGFloat = 12
    static let cardHeight: CGFloat = 150
    static let cardRadius: CGFloat = 12
    static let chatColumns = Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: 3)
    static let routineColumns = Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: 2)
}

struct StartPageLibrary: View {
    private static let visibleConversationCount = 3

    @Bindable var model: WindowModel
    let targetNodeID: UUID?
    @ViewState private var selection = StartPageLibraryTab.chats
    @ViewState private var editingRoutine: AssistantRoutine?

    private var store: AssistantRoutineStore { AssistantRoutineStore.shared }

    private var conversations: [StoredConversation] {
        Array(ConversationStore.shared.list(profileID: model.profileID).prefix(Self.visibleConversationCount))
    }

    private var routines: [AssistantRoutine] {
        store.list(profileID: model.profileID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                LibraryTabPicker(selection: $selection)
                Spacer()
                headerAction
            }
            switch selection {
            case .chats:
                chatCards
            case .routines:
                routineList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $editingRoutine) { routine in
            RoutineEditorSheet(routine: routine, spaces: model.spaces, isNew: !store.routines.contains { $0.id == routine.id }, onSave: store.save)
        }
    }

    @ViewBuilder
    private var headerAction: some View {
        switch selection {
        case .chats:
            LibraryHeaderButton(title: "Todos los chats", symbolName: "chevron.right") { model.isHistoryPresented = true }
        case .routines:
            LibraryHeaderButton(title: "Nueva rutina", symbolName: "plus", action: createRoutine)
        }
    }

    @ViewBuilder
    private var chatCards: some View {
        if conversations.isEmpty {
            LibraryEmptyCard(
                symbolName: "bubble.left.and.bubble.right",
                title: "Tus chats recientes aparecen acá",
                detail: "Pregúntale algo a la IA y vas a poder retomarlo desde esta página."
            )
        } else {
            LazyVGrid(columns: LibraryMetrics.chatColumns, alignment: .leading, spacing: LibraryMetrics.spacing) {
                ForEach(conversations) { conversation in
                    ConversationPreviewCard(conversation: conversation) {
                        model.openConversation(conversation.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var routineList: some View {
        if routines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Todavía no tienes rutinas. Empieza con una plantilla:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: LibraryMetrics.routineColumns, alignment: .leading, spacing: 4) {
                    ForEach(RoutineTemplate.all) { template in
                        RoutineRow(symbolName: template.symbolName, routine: template.makeRoutine(profileID: model.profileID)) {
                            editingRoutine = template.makeRoutine(profileID: model.profileID)
                        }
                    }
                }
            }
        } else {
            LazyVGrid(columns: LibraryMetrics.routineColumns, alignment: .leading, spacing: 4) {
                ForEach(routines) { routine in
                    RoutineRow(symbolName: routine.symbolName, routine: routine) { run(routine) }
                        .contextMenu {
                            Button("Ejecutar ahora", systemImage: "play") { run(routine) }
                            Button("Editar…", systemImage: "pencil") { editingRoutine = routine }
                            Divider()
                            Button("Eliminar", systemImage: "trash", role: .destructive) { store.delete(routine.id) }
                        }
                }
            }
        }
    }

    private func createRoutine() {
        editingRoutine = AssistantRoutine(profileID: model.profileID)
    }

    private func run(_ routine: AssistantRoutine) {
        model.run(routine, in: targetNodeID)
    }
}

private struct LibraryTabPicker: View {
    @Binding var selection: StartPageLibraryTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StartPageLibraryTab.allCases, content: tabButton)
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func tabButton(_ tab: StartPageLibraryTab) -> some View {
        let isSelected = selection == tab
        return Button { withAnimation(.snappy) { selection = tab } } label: {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(isSelected ? Color(nsColor: .textBackgroundColor) : Color.clear).shadow(color: .black.opacity(isSelected ? 0.1 : 0), radius: 2, y: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LibraryHeaderButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: symbolName, action: action)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }
}

struct RoutineRow: View {
    let symbolName: String
    let routine: AssistantRoutine
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(routine.summary.isEmpty ? routine.prompt : routine.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Label(routine.scheduleDescription, systemImage: routine.schedule == .manual ? "hand.tap" : "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .hoverHighlight(cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }
}

struct RoutineTemplate: Identifiable {
    let symbolName: String
    let title: String
    let summary: String
    let prompt: String
    let schedule: RoutineSchedule
    let hour: Int
    let minute: Int

    var id: String { title }

    func makeRoutine(profileID: UUID) -> AssistantRoutine {
        AssistantRoutine(profileID: profileID, title: title, summary: summary, prompt: prompt, usesAgent: true, schedule: schedule, hour: hour, minute: minute)
    }

    static let all = [
        RoutineTemplate(
            symbolName: "newspaper",
            title: "Briefing de noticias",
            summary: "Las noticias más importantes del día, resumidas.",
            prompt: "Busca las noticias más importantes de hoy en tecnología, economía y mi país. Resume cada una en dos líneas con el link a la fuente.",
            schedule: .weekdays, hour: 8, minute: 30
        ),
        RoutineTemplate(
            symbolName: "tray.full",
            title: "Triage de correo",
            summary: "Prioriza tu bandeja y propone respuestas para lo urgente.",
            prompt: "Abre Gmail, revisa los correos no leídos de las últimas 24 horas y clasifícalos en urgente, para responder y para leer después. Propón un borrador corto para los urgentes.",
            schedule: .weekdays, hour: 9, minute: 0
        ),
        RoutineTemplate(
            symbolName: "arrow.triangle.pull",
            title: "Resumen de pull requests",
            summary: "PRs abiertos, estado de revisión y qué necesita atención.",
            prompt: "Entra a GitHub, revisa mis pull requests abiertos y los que esperan mi revisión. Dime cuáles necesitan atención y por qué.",
            schedule: .weekdays, hour: 14, minute: 0
        ),
        RoutineTemplate(
            symbolName: "tag",
            title: "Seguimiento de precios",
            summary: "Avisa si bajó el precio de algo que quieres comprar.",
            prompt: "Busca el precio actual de [producto] en las tiendas principales y dime dónde está más barato y si bajó respecto a la semana pasada.",
            schedule: .weekly, hour: 10, minute: 0
        ),
    ]
}

struct ConversationPreviewCard: View {
    let conversation: StoredConversation
    let action: () -> Void

    private var preview: String {
        conversation.preview.isEmpty ? "Continúa la conversación donde la dejaste." : conversation.preview
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(conversation.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(conversation.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: LibraryMetrics.cardHeight, maxHeight: LibraryMetrics.cardHeight, alignment: .topLeading)
            .libraryCardChrome()
        }
        .buttonStyle(.plain)
        .help("Abrir conversación")
    }
}

struct LibraryEmptyCard: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .libraryCardChrome()
    }
}

private extension View {
    func libraryCardChrome() -> some View {
        let shape = RoundedRectangle(cornerRadius: LibraryMetrics.cardRadius, style: .continuous)
        return background(shape.fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            .contentShape(shape)
    }
}
