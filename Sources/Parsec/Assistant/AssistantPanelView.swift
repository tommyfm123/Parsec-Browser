import AppKit
import SwiftUI

struct AssistantPanelView: View {
    static let width = AssistantPanelMetrics.width

    @Bindable var model: WindowModel
    @Bindable var assistant: AssistantModel
    var isFloating = false
    @ViewState private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            AgentHeader(model: model, isFloating: isFloating)
            if assistant.messages.isEmpty {
                VStack(spacing: 24) {
                    Spacer()
                    AgentWelcome()
                    AgentComposer(model: model, assistant: assistant)
                    Spacer()
                    Spacer()
                }
            } else {
                AgentConversation(model: model, assistant: assistant)
                AgentComposer(model: model, assistant: assistant)
            }
        }
        .id(assistant.id)
        .foregroundStyle(Color.primary)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.window, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: Radius.window, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Radius.window, style: .continuous).strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.7 : 0), lineWidth: 2))
        .overlay(IntelligenceGlow(isActive: model.agents.contains(where: \.isRunning), cornerRadius: Radius.window))
        .shadow(color: .black.opacity(isFloating ? 0.22 : 0.06), radius: isFloating ? 26 : 8, y: 4)
        .dropDestination(for: URL.self) { urls, _ in
            urls.filter(\.isFileURL).forEach(assistant.attach)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onAppear { assistant.refreshSelection() }
        .onChange(of: model.activePage?.currentURL) { assistant.refreshSelection() }
    }
}

enum UserIdentity {
    @MainActor static var firstName: String {
        BrowserStore.shared.settings.userProfile.firstName
            ?? NSFullUserName().split(separator: " ").first.map(String.init)
            ?? NSUserName()
    }
}

struct ProviderLogo: View {
    let provider: AssistantProviderKind
    var size: CGFloat = 30

    var body: some View {
        FaviconView(url: provider.logoURL, size: size)
            .frame(width: size, height: size)
    }
}

struct AgentHeader: View {
    @Bindable var model: WindowModel
    let isFloating: Bool

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(model.agents) { agent in
                        AgentTab(agent: agent, isSelected: agent.id == model.activeAgentID, canClose: model.agents.count > 1) {
                            model.selectAgent(agent.id)
                        } onClose: {
                            model.closeAgent(agent.id)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            IconButton(symbolName: "plus", label: "Nuevo agente") { model.newAgent() }
            ParsecDropdown(width: 230, entries: panelEntries) {
                DropdownIconLabel(symbolName: "ellipsis")
            }
            .accessibilityLabel("Opciones del panel")
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
    }

    private func panelEntries() -> [MenuEntry] {
        [
            .action(isFloating ? "Fijar panel" : "Soltar panel", symbol: isFloating ? "pin" : "pin.slash") {
                model.isAssistantPresented.toggle()
                model.isAssistantHovering = false
            },
            .action("Nueva conversación", symbol: "square.and.pencil") { model.assistant.startNewConversation() },
            .action("Historial", symbol: "clock.arrow.circlepath", shortcut: "⌘Y", isEnabled: !model.isPrivate) { model.isHistoryPresented = true },
            .divider,
            .action("Configurar proveedores…", symbol: "gearshape") { AppDelegate.shared.openSettings(section: .assistant) },
            .action("Cerrar panel", symbol: "xmark", shortcut: "⌘J") {
                model.isAssistantPresented = false
                model.isAssistantHovering = false
            },
        ]
    }
}

struct AgentTab: View {
    @Bindable var agent: AssistantModel
    let isSelected: Bool
    let canClose: Bool
    let action: () -> Void
    let onClose: () -> Void
    @ViewState private var isHovering = false
    @ViewState private var isRenaming = false

    var body: some View {
        HStack(spacing: 6) {
            AgentStatusIndicator(isRunning: agent.isRunning, hasUnseenResult: agent.hasUnseenResult)
            if isRenaming {
                InlineRenameField(initialText: agent.title, font: .system(size: 12, weight: .semibold), onFinish: finishRenaming)
                    .frame(width: 120)
            } else {
                Text(agent.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
            }
            if canClose && isHovering && !isRenaming {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Cerrar agente")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .background(Capsule().fill(Color.primary.opacity(isSelected ? 0.09 : isHovering ? 0.05 : 0)))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
        .clickable()
        .contextMenu {
            Button { isRenaming = true } label: { Label("Renombrar", systemImage: "pencil") }
            Button(role: .destructive, action: onClose) { Label("Cerrar", systemImage: "xmark") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func finishRenaming(_ newName: String?) {
        guard isRenaming else { return }
        isRenaming = false
        guard let newName else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        agent.customTitle = trimmedName.isEmpty ? nil : trimmedName
    }
}

struct AgentStatusIndicator: View {
    let isRunning: Bool
    let hasUnseenResult: Bool

    var body: some View {
        Group {
            if isRunning {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(hasUnseenResult ? Color.accentColor : Color.primary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 12, height: 12)
    }
}

struct AgentSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct AgentWelcome: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("Hola, \(UserIdentity.firstName).")
            Text("¿Qué quieres hacer hoy?").foregroundStyle(.secondary)
        }
        .font(.system(size: 25, weight: .regular, design: .serif))
        .tracking(-0.4)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}

struct IntelligenceGlow: View {
    private static let colors: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 1), Color(red: 0.7, green: 0.4, blue: 1), Color(red: 1, green: 0.42, blue: 0.62),
        Color(red: 1, green: 0.66, blue: 0.3), Color(red: 0.36, green: 0.55, blue: 1),
    ]
    private static let rotationPeriod = 4.0

    let isActive: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.rotationPeriod) / Self.rotationPeriod * 360
            let gradient = AngularGradient(colors: Self.colors, center: .center, angle: .degrees(angle))
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(gradient, lineWidth: 2)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(gradient, lineWidth: 8).blur(radius: 10).opacity(0.6)
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: 0.5), value: isActive)
        .allowsHitTesting(false)
    }
}

struct CommandRow: View {
    let command: AgentCommand
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: command.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title).font(.system(size: 12, weight: .medium))
                    Text(command.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("/\(command.keyword)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 8, isActive: isHighlighted)
    }
}

struct AgentConversation: View {
    @Bindable var model: WindowModel
    @Bindable var assistant: AssistantModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(assistant.messages) { message in
                        AgentMessageView(model: model, assistant: assistant, message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .onChange(of: assistant.messages.last?.text) { scrollToBottom(proxy) }
            .onChange(of: assistant.messages.last?.steps.count) { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastID = assistant.messages.last?.id else { return }
        proxy.scrollTo(lastID, anchor: .bottom)
    }
}

struct AgentMessageView: View {
    @Bindable var model: WindowModel
    @Bindable var assistant: AssistantModel
    @Bindable var message: AssistantMessage
    var textSize: CGFloat = 13

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 5) {
                Text(message.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))
                if !message.contextLabels.isEmpty || !message.attachments.isEmpty {
                    Text((message.contextLabels + message.attachments.map(\.name)).joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                if !message.steps.isEmpty {
                    StepList(steps: message.steps, isBrowsing: message.isBrowsing, isStreaming: message.isStreaming)
                }
                if !message.text.isEmpty {
                    MarkdownText(text: message.text, fontSize: textSize)
                        .foregroundStyle(message.isError ? Color.red : Color.primary)
                }
                if !message.sources.isEmpty {
                    SourcesView(sources: message.sources) { _ = model.openInNewTab($0.url) }
                }
                if !message.actions.isEmpty {
                    PlanCard(assistant: assistant, message: message)
                }
                if !message.isStreaming && !message.isError && !message.text.isEmpty {
                    IconButton(symbolName: "doc.on.doc", label: "Copiar respuesta") { Clipboard.copy(message.text) }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StepList: View {
    private static let collapsedLimit = 4

    let steps: [AgentStep]
    let isBrowsing: Bool
    let isStreaming: Bool
    @ViewState private var isExpanded = false

    private var visibleSteps: [AgentStep] {
        isExpanded || steps.count <= Self.collapsedLimit ? steps : Array(steps.suffix(Self.collapsedLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isBrowsing {
                HStack(spacing: 6) {
                    Image(systemName: "cursorarrow.motionlines").font(.system(size: 11, weight: .semibold))
                    Text(isStreaming ? "Navegando por ti" : steps.count == 1 ? "Navegó 1 paso" : "Navegó \(steps.count) pasos")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if steps.count > Self.collapsedLimit {
                        Button(isExpanded ? "Ver menos" : "Ver todo") { withAnimation(.snappy) { isExpanded.toggle() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(isStreaming ? Color.primary : Color.secondary)
            }
            ForEach(visibleSteps) { step in
                StepRow(step: step)
            }
        }
        .padding(isBrowsing ? 12 : 0)
        .background {
            if isBrowsing {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.primary.opacity(0.04))
            }
        }
        .animation(.snappy, value: steps.count)
    }
}

struct StepRow: View {
    @Bindable var step: AgentStep
    private var showsDetail: Bool { BrowserStore.shared.settings.developerMode && step.detail != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Group {
                    switch step.state {
                    case .running: ProgressView().controlSize(.mini)
                    case .done: Image(systemName: "checkmark").foregroundStyle(.secondary)
                    case .failed: Image(systemName: "xmark").foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 9, weight: .bold))
                .frame(width: 12, height: 12)
                Image(systemName: step.symbolName).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 14)
                Text(step.title)
                    .font(.system(size: 11.5, weight: step.state == .running ? .medium : .regular))
                    .foregroundStyle(step.state == .running ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            if showsDetail, let detail = step.detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .padding(.leading, 33)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct SourcesView: View {
    let sources: [AgentSource]
    let onOpen: (AgentSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fuentes · \(sources.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        SourceCard(index: index + 1, source: source) { onOpen(source) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

struct SourceCard: View {
    let index: Int
    let source: AgentSource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(source.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                HStack(spacing: 5) {
                    FaviconView(url: source.url, size: 12)
                    Text(source.host).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(index)").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .frame(width: 150)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .help(source.url.absoluteString)
    }
}

struct PlanCard: View {
    @Bindable var assistant: AssistantModel
    @Bindable var message: AssistantMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AgentSectionTitle(title: "Plan · \(message.actions.count) pasos")
                Spacer()
                status
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            Divider().opacity(0.5)
            ForEach(Array(message.actions.enumerated()), id: \.offset) { index, action in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                    Image(systemName: action.symbolName).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
                    Text(action.summary).font(.system(size: 12)).lineLimit(2)
                    Spacer(minLength: 0)
                    stepResult(for: action)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            if message.actionState == .pending {
                Divider().opacity(0.5)
                HStack {
                    Spacer()
                    Button("Descartar") { assistant.dismissActions(of: message) }.buttonStyle(.borderless)
                    Button("Ejecutar plan") { assistant.runActions(of: message) }.buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
                .padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    @ViewBuilder
    private var status: some View {
        switch message.actionState {
        case .pending: Text("Requiere aprobación").font(.system(size: 10)).foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.mini)
        case .done: Text(message.actionFailures.isEmpty ? "Completado" : "Con errores").font(.system(size: 10, weight: .medium)).foregroundStyle(message.actionFailures.isEmpty ? Color.green : Color.orange)
        case .dismissed: Text("Descartado").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stepResult(for action: BrowserAction) -> some View {
        if message.actionState == .done {
            let failed = message.actionFailures.contains(action.summary)
            Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(failed ? Color.orange : Color.green)
        }
    }
}

struct ContextChip: View {
    let title: String
    let symbolName: String
    let iconURL: URL?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            if let iconURL {
                FaviconView(url: iconURL, size: 12)
            } else {
                Image(systemName: symbolName).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Quitar \(title)")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct AgentComposer: View {
    @Bindable var model: WindowModel
    @Bindable var assistant: AssistantModel
    @FocusState private var isFocused: Bool
    @ViewState private var highlightedCommandIndex = 0

    private var commands: [AgentCommand] { assistant.matchingCommands }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !commands.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        CommandRow(command: command, isHighlighted: index == highlightedCommandIndex) { choose(command) }
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if !assistant.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(assistant.pendingAttachments) { attachment in
                            ContextChip(title: attachment.name, symbolName: attachment.symbolName, iconURL: nil) { assistant.removeAttachment(attachment) }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                ContextMenuChip(assistant: assistant)
                Spacer(minLength: 0)
                ModelPicker(compact: true)
            }
            .padding(.horizontal, 4)
            ComposerField(model: model, assistant: assistant, isFocused: $isFocused, onSubmit: submit, onMoveHighlight: moveHighlight)
                .onChange(of: assistant.draft) { highlightedCommandIndex = 0 }
        }
        .padding(12)
        .animation(.easeOut(duration: 0.15), value: commands.isEmpty)
        .onAppear { isFocused = true }
    }

    private func choose(_ command: AgentCommand) {
        assistant.draft = ""
        assistant.perform(command)
        isFocused = true
    }

    private func submit() {
        guard !commands.isEmpty, commands.indices.contains(highlightedCommandIndex) else { return assistant.send() }
        choose(commands[highlightedCommandIndex])
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        guard !commands.isEmpty else { return .ignored }
        highlightedCommandIndex = (highlightedCommandIndex + offset + commands.count) % commands.count
        return .handled
    }
}

struct ComposerField: View {
    private static let controlSize: CGFloat = 30
    private static let singleLineHeight: CGFloat = 20
    private static let expandedRadius: CGFloat = 20
    private static let fontSize: CGFloat = 13.5

    @Bindable var model: WindowModel
    @Bindable var assistant: AssistantModel
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onMoveHighlight: (Int) -> KeyPress.Result
    @ViewState private var isMultiline = false
    @ViewState private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isMultiline ? Self.expandedRadius : (Self.controlSize + 10) / 2, style: .continuous)
    }

    private var placeholder: Text {
        Text("Escribe un mensaje o usa ") + Text("/").font(.system(size: Self.fontSize, weight: .semibold, design: .monospaced)) + Text(" para comandos")
    }

    private var strokeOpacity: Double {
        isFocused.wrappedValue ? 0.2 : isHovering ? 0.14 : 0.09
    }

    var body: some View {
        HStack(alignment: isMultiline ? .bottom : .center, spacing: 6) {
            ComposerPlusMenu(model: model, assistant: assistant)
            TextField("", text: $assistant.draft, prompt: placeholder, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: Self.fontSize))
                .lineSpacing(2)
                .lineLimit(1...8)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .onKeyPress(.upArrow) { onMoveHighlight(-1) }
                .onKeyPress(.downArrow) { onMoveHighlight(1) }
                .onKeyPress(.escape) {
                    guard !assistant.draft.isEmpty else { return .ignored }
                    assistant.draft = ""
                    return .handled
                }
                .onGeometryChange(for: Bool.self) { $0.size.height > Self.singleLineHeight * 1.5 } action: { expanded in
                    withAnimation(.snappy(duration: 0.2)) { isMultiline = expanded }
                }
                .padding(.vertical, isMultiline ? 6 : 0)
                .frame(minHeight: Self.controlSize)
            SendButton(assistant: assistant)
        }
        .padding(5)
        .background(shape.fill(Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .textBackgroundColor)))
        .overlay(shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.08 : 0.5), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        .background(shape.stroke(Color.accentColor.opacity(isFocused.wrappedValue ? 0.18 : 0), lineWidth: 4).blur(radius: 2))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.07), radius: isFocused.wrappedValue ? 14 : 8, y: 3)
        .contentShape(shape)
        .onTapGesture { isFocused.wrappedValue = true }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isFocused.wrappedValue)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

struct ContextMenuChip: View {
    private static let tabLimit = 20

    @Bindable var assistant: AssistantModel

    var body: some View {
        ParsecDropdown(width: 270, entries: entries) {
            HStack(spacing: 5) {
                Image(systemName: assistant.contextScope.symbolName).font(.system(size: 10, weight: .semibold))
                Text("Contexto: \(assistant.contextLabel)").font(.system(size: 11, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .contentShape(Capsule())
            .hoverHighlight(cornerRadius: 12)
        }
        .help("Qué puede ver el agente")
    }

    private func entries() -> [MenuEntry] {
        let scopes = [ContextScope.page, .space, .none].map { scope in
            MenuEntry.action(scope.title, symbol: scope.symbolName, isSelected: assistant.contextScope == scope) {
                assistant.selectedTabIDs.removeAll()
                assistant.contextScope = scope
            }
        }
        let tabs = assistant.spaceTabs.prefix(Self.tabLimit).map { tab in
            MenuEntry.action(tab.displayTitle, iconURL: tab.liveURL, isSelected: assistant.selectedTabIDs.contains(tab.id), keepsOpen: true) {
                assistant.toggleTab(tab.id)
            }
        }
        return scopes + (tabs.isEmpty ? [] : [.header("Elegir páginas")] + tabs)
    }
}

struct ModelPicker: View {
    var compact = false
    @ViewState private var isPresented = false
    private var current: ModelOption { ModelCatalog.current }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 6) {
                ProviderLogo(provider: current.provider, size: compact ? 13 : 14)
                Text(current.title).font(.system(size: compact ? 11.5 : 12, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
            .foregroundStyle(isPresented ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: compact ? 26 : 30)
            .background(Capsule().fill(Color.primary.opacity(isPresented ? 0.12 : 0.055)))
            .contentShape(Capsule())
            .hoverHighlight(cornerRadius: compact ? 13 : 15)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Elegir modelo de IA")
        .accessibilityLabel("Modelo: \(current.title)")
        .animation(.snappy(duration: 0.2), value: isPresented)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ModelPickerPopover { isPresented = false }
        }
    }
}

struct ModelPickerPopover: View {
    let onDismiss: () -> Void
    private var localModels: LocalModels { LocalModels.shared }
    private var current: ModelOption { ModelCatalog.current }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.never)
        }
        .frame(width: 320)
        .frame(maxHeight: 520)
        .task { await localModels.refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(ModelCatalog.availableProviders.filter { $0 != .localModels }) { provider in
                ModelSection(provider: provider) {
                    ForEach(ModelCatalog.options(for: provider)) { option in
                        ModelOptionRow(option: option, isSelected: option == current) { choose(option) }
                    }
                }
            }
            ModelSection(provider: .localModels) {
                ForEach(ModelCatalog.options(for: .localModels)) { option in
                    ModelOptionRow(option: option, isSelected: option == current) { choose(option) }
                }
                if localModels.isServerRunning {
                    ForEach(LocalModels.suggestions.filter { !localModels.isInstalled($0.name) }) { suggestion in
                        LocalModelDownloadRow(suggestion: suggestion, progress: localModels.downloadProgress[suggestion.name]) {
                            localModels.download(suggestion.name)
                        }
                    }
                } else {
                    OllamaInstallRow()
                }
            }
            Divider().padding(.horizontal, 4)
            PopoverActionRow(title: "Configurar proveedores…", symbolName: "gearshape") {
                onDismiss()
                AppDelegate.shared.openSettings(section: .assistant)
            }
        }
        .padding(10)
    }

    private func choose(_ option: ModelOption) {
        ModelCatalog.select(option)
        onDismiss()
    }
}

struct ModelSection<Content: View>: View {
    let provider: AssistantProviderKind
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(provider.pickerTitle)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            content
        }
    }
}

struct ModelOptionRow: View {
    let option: ModelOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProviderLogo(provider: option.provider, size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.system(size: 13, weight: .medium))
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(isSelected ? 0.14 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .hoverHighlight(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct LocalModelDownloadRow: View {
    let suggestion: LocalModels.Suggestion
    let progress: Double?
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.name).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(suggestion.detail).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .help("Descargando \(Int(progress * 100)) %")
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .clickable()
                .help("Descargar \(suggestion.name)")
                .accessibilityLabel("Descargar \(suggestion.name)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

struct OllamaInstallRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Para usar modelos en tu Mac, sin conexión y gratis, instala Ollama y ábrelo.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Descargar Ollama") { NSWorkspace.shared.open(LocalModels.downloadURL) }
                    .liquidGlassButton(prominent: true)
                    .clickable()
                Button("Ya lo abrí") { Task { await LocalModels.shared.refresh() } }
                    .liquidGlassButton()
                    .clickable()
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
    }
}

struct PopoverActionRow: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .hoverHighlight(cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }
}

struct ComposerPlusMenu: View {
    @Bindable var model: WindowModel
    @Bindable var assistant: AssistantModel
    private var store: BrowserStore { BrowserStore.shared }
    private var catalog: ConnectorCatalog { ConnectorCatalog.shared }

    var body: some View {
        ParsecDropdown(width: 290, arrowEdge: .top, entries: entries) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .hoverHighlight(cornerRadius: 15)
        }
        .help("Adjuntar, herramientas y navegación")
        .accessibilityLabel("Adjuntar y herramientas")
        .onAppear { catalog.loadIfNeeded() }
    }

    private func entries() -> [MenuEntry] {
        let usesWebSearch = store.settings.assistantUsesWebSearch
        var entries: [MenuEntry] = [
            .action("Adjuntar archivos…", symbol: "paperclip") { assistant.attachFiles() },
            .action("Captura de la página", symbol: "camera.viewfinder", isEnabled: model.activePage != nil) { assistant.attachScreenshot() },
            .divider,
            .action("Market research", symbol: "chart.bar.doc.horizontal", detail: "Navega, investiga y cita fuentes") { assistant.draft = "/market-research " },
            .action("Navegar por mí", symbol: "cursorarrow.motionlines", detail: "El agente usa el navegador") { assistant.draft = "/navegar " },
            .divider,
            .action("Búsqueda web", symbol: "globe", isSelected: usesWebSearch, isEnabled: assistant.provider.supportsWebSearch, keepsOpen: true) {
                store.settings.assistantUsesWebSearch.toggle()
                store.saveSoon()
            },
        ]
        guard assistant.provider.supportsConnectors else { return entries }
        entries.append(.header("Conectores"))
        guard !catalog.connectors.isEmpty else {
            return entries + [.action(catalog.isLoading ? "Buscando conectores…" : "No hay conectores en Claude Code", isEnabled: false) {}]
        }
        return entries + catalog.connectors.map { connector in
            .action(connector, symbol: "puzzlepiece.extension", isSelected: store.settings.assistantConnectors.contains(connector), keepsOpen: true) {
                toggle(connector)
            }
        }
    }

    private func toggle(_ connector: String) {
        if store.settings.assistantConnectors.contains(connector) {
            store.settings.assistantConnectors.remove(connector)
        } else {
            store.settings.assistantConnectors.insert(connector)
        }
        store.saveSoon()
    }
}

struct SendButton: View {
    private static let size: CGFloat = 30

    @Bindable var assistant: AssistantModel
    @ViewState private var isHovering = false

    private var isActive: Bool { assistant.isRunning || assistant.canSend }

    var body: some View {
        Button {
            assistant.isRunning ? assistant.stop() : assistant.send()
        } label: {
            ZStack {
                Circle().fill(isActive ? Color.primary : Color.primary.opacity(0.07))
                if assistant.isRunning {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .frame(width: 9, height: 9)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(Color(nsColor: .textBackgroundColor))
                        .opacity(0.5)
                        .scaleEffect(1.05)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(isActive ? Color(nsColor: .textBackgroundColor) : Color.secondary.opacity(0.7))
                }
            }
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(isActive && isHovering ? 1.06 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
        .onHover { isHovering = $0 }
        .clickable()
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        .keyboardShortcut(.return, modifiers: .command)
        .help(assistant.isRunning ? "Detener" : "Enviar (↩)")
        .accessibilityLabel(assistant.isRunning ? "Detener" : "Enviar")
    }
}
