import SwiftUI

struct RoutineEditorSheet: View {
    private static let sheetWidth: CGFloat = 540
    private static let fieldRadius: CGFloat = 8
    private static let currentSpaceTitle = "Space actual"

    @Environment(\.dismiss) private var dismiss
    @ViewState private var routine: AssistantRoutine
    let spaces: [Space]
    let isNew: Bool
    let onSave: (AssistantRoutine) -> Void

    init(routine: AssistantRoutine, spaces: [Space], isNew: Bool, onSave: @escaping (AssistantRoutine) -> Void) {
        _routine = ViewState(initialValue: routine)
        self.spaces = spaces
        self.isNew = isNew
        self.onSave = onSave
    }

    private var canSave: Bool {
        [routine.title, routine.summary, routine.prompt].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var spaceOptions: [(value: UUID?, title: String)] {
        [(nil, Self.currentSpaceTitle)] + spaces.map { ($0.id, $0.title) }
    }

    private var weekdayOptions: [(value: Int, title: String)] {
        AssistantRoutine.weekdayNames.enumerated().map { ($0.offset + 1, $0.element.capitalized) }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: routine.hour, minute: routine.minute)) ?? Date() },
            set: updateTime
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "Nueva rutina" : "Editar rutina")
                .font(.system(size: 19, weight: .semibold))
            Label("Las rutinas programadas solo corren mientras Parsec está abierto.", systemImage: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Self.fieldRadius, style: .continuous).fill(Color.primary.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: Self.fieldRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            RoutineFormField(title: "Nombre", isRequired: true) {
                RoutineTextField(placeholder: "Resumen de noticias", text: $routine.title)
            }
            RoutineFormField(title: "Descripción", isRequired: true) {
                RoutineTextField(placeholder: "Las noticias clave del día en dos minutos", text: $routine.summary)
            }
            RoutineFormField(title: "Instrucciones", isRequired: true) {
                instructionsBox
            }
            RoutineFormField(title: "Programación", isRequired: false) {
                scheduleControls
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button(isNew ? "Crear" : "Guardar", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: Self.sheetWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var instructionsBox: some View {
        VStack(spacing: 0) {
            TextEditor(text: $routine.prompt)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(.horizontal, 6)
                .padding(.top, 8)
            HStack {
                ParsecSegmented(selection: $routine.usesAgent, options: [(false, "Preguntar"), (true, "Agente")])
                Spacer()
                Text(routine.usesAgent ? "Navega y usa tus pestañas" : "Responde en un chat nuevo")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            HStack(spacing: 8) {
                Image(systemName: "square.stack")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Correr en")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ParsecSelect(selection: $routine.spaceID, options: spaceOptions, width: 180)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.035))
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.fieldRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.fieldRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    private var scheduleControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParsecSegmented(selection: $routine.schedule, options: RoutineSchedule.allCases.map { ($0, $0.title) })
            if routine.schedule != .manual {
                HStack(spacing: 8) {
                    if routine.schedule == .weekly {
                        Text("Los").font(.system(size: 12)).foregroundStyle(.secondary)
                        ParsecSelect(selection: $routine.weekday, options: weekdayOptions, width: 130)
                    }
                    if routine.schedule.usesTime {
                        Text("a las").font(.system(size: 12)).foregroundStyle(.secondary)
                        DatePicker("Hora", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                    } else {
                        Stepper(String(format: "Al minuto %02d", routine.minute), value: $routine.minute, in: 0...59)
                            .font(.system(size: 12))
                            .fixedSize()
                    }
                }
            }
            Text(routine.scheduleDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func updateTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        routine.hour = components.hour ?? routine.hour
        routine.minute = components.minute ?? routine.minute
    }

    private func save() {
        guard canSave else { return }
        routine.title = routine.title.trimmingCharacters(in: .whitespacesAndNewlines)
        routine.summary = routine.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        routine.prompt = routine.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        routine.lastRunAt = Date()
        onSave(routine)
        dismiss()
    }
}

private struct RoutineFormField<Content: View>: View {
    let title: String
    let isRequired: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                if isRequired {
                    Text("*").font(.system(size: 12, weight: .medium)).foregroundStyle(.red)
                }
            }
            content
        }
    }
}

private struct RoutineTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($isFocused)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isFocused ? 1.5 : 1))
    }
}
