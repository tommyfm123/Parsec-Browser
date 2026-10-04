import SwiftUI

struct MiniPopupView: View {
    @Bindable var model: WindowModel
    @Bindable var assistant: AssistantModel
    let onCardHeightChange: (CGFloat) -> Void
    let onNewConversation: () -> Void
    let onContinueInBrowser: () -> Void
    let onClose: () -> Void
    @ViewState private var draft = ""
    @ViewState private var mode = StartMode.ask
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MiniPopupMetrics.cardRadius, style: .continuous)
    }

    private var hasConversation: Bool { !assistant.messages.isEmpty }

    private var activePage: WebPage? {
        guard mode == .ask, let page = model.activePage, page.currentURL != nil else { return nil }
        return page
    }

    private var showsChips: Bool {
        activePage != nil || !assistant.pendingAttachments.isEmpty
    }

    private var canSubmit: Bool {
        assistant.isRunning || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cardAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }

    var body: some View {
        card
            .frame(width: MiniPopupMetrics.cardWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: \.size.height, action: onCardHeightChange)
            .padding(MiniPopupMetrics.shadowInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(cardAnimation, value: hasConversation)
            .animation(cardAnimation, value: showsChips)
            .onAppear(perform: focusField)
            .onExitCommand(perform: onClose)
            .onReceive(NotificationCenter.default.publisher(for: MiniPopupController.didShowNotification)) { _ in focusField() }
            .onChange(of: hasConversation, conversationToggled)
    }

    private var card: some View {
        VStack(spacing: 0) {
            if hasConversation {
                MiniPopupHeader(
                    title: assistant.title,
                    canContinueInBrowser: model.window != nil,
                    onNewConversation: onNewConversation,
                    onContinueInBrowser: onContinueInBrowser,
                    onClose: onClose
                )
                conversation
                Divider().opacity(0.6)
            }
            composer
        }
        .clipShape(cardShape)
        .liquidGlass(in: cardShape)
        .overlay(cardShape.strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(assistant.messages.suffix(8)) { message in
                        AgentMessageView(model: model, assistant: assistant, message: message, textSize: 13)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.never)
            .frame(height: MiniPopupMetrics.conversationHeight)
            .onChange(of: assistant.messages.last?.text) {
                guard let lastID = assistant.messages.last?.id else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputRow
            if showsChips {
                chips.transition(.opacity)
            }
            toolbar
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var inputRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: mode.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            TextField(mode.placeholder, text: $draft, axis: .vertical)
                .font(.system(size: 17))
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(submit)
                .onKeyPress(.tab, action: cycleMode)
                .accessibilityLabel(mode.title)
        }
        .padding(.horizontal, 2)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let activePage {
                    PageContextToggle(page: activePage, isOn: assistant.contextScope == .page, onToggle: togglePageContext)
                }
                ForEach(assistant.pendingAttachments) { attachment in
                    ContextChip(title: attachment.name, symbolName: attachment.symbolName, iconURL: nil) { assistant.removeAttachment(attachment) }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            MiniPopupIconButton(symbolName: "plus", help: "Adjuntar archivos", action: assistant.attachFiles)
            MiniPopupModePicker(selection: mode, onSelect: selectMode)
            Spacer(minLength: 4)
            ModelPicker(compact: true)
            sendButton
        }
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: assistant.isRunning ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.background)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(canSubmit ? 1 : 0.25)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .help(assistant.isRunning ? "Detener" : mode.title)
        .accessibilityLabel(assistant.isRunning ? "Detener" : mode.title)
    }

    private func submit() {
        guard !assistant.isRunning else { return assistant.stop() }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        switch mode {
        case .search:
            guard let destination = InputResolver.destination(for: text) else { return }
            _ = model.openInNewTab(destination)
            onClose()
        case .ask:
            assistant.send(text)
        case .browse:
            assistant.browse(text)
        }
    }

    private func togglePageContext() {
        assistant.contextScope = assistant.contextScope == .page ? .none : .page
        focusField()
    }

    private func selectMode(_ candidate: StartMode) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { mode = candidate }
        focusField()
    }

    private func cycleMode() -> KeyPress.Result {
        selectMode(mode.next)
        return .handled
    }

    private func conversationToggled(_: Bool, _ hasConversation: Bool) {
        guard !hasConversation else { return }
        draft = ""
        mode = .ask
    }

    private func focusField() {
        isFocused = true
    }
}

private struct MiniPopupHeader: View {
    let title: String
    let canContinueInBrowser: Bool
    let onNewConversation: () -> Void
    let onContinueInBrowser: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            MiniPopupIconButton(symbolName: "square.and.pencil", help: "Nuevo chat", action: onNewConversation)
            if canContinueInBrowser {
                MiniPopupIconButton(symbolName: "arrow.up.left.and.arrow.down.right", help: "Continuar en el panel de Parsec", action: onContinueInBrowser)
            }
            MiniPopupIconButton(symbolName: "xmark", help: "Cerrar", action: onClose)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.top, 10)
    }
}

private struct MiniPopupIconButton: View {
    let symbolName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .hoverHighlight(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct MiniPopupModePicker: View {
    let selection: StartMode
    let onSelect: (StartMode) -> Void
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StartMode.allCases, id: \.self, content: modeButton)
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modo")
    }

    private func modeButton(_ mode: StartMode) -> some View {
        let isSelected = mode == selection
        return Button { onSelect(mode) } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.symbolName).font(.system(size: 10, weight: .semibold))
                Text(mode.title).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(mode.title) · Tab para cambiar")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PageContextToggle: View {
    let page: WebPage
    let isOn: Bool
    let onToggle: () -> Void

    private var pageTitle: String {
        page.title.isEmpty ? page.currentURL?.host() ?? "Página actual" : page.title
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                FaviconView(url: page.currentURL, size: 13, isDimmed: !isOn, allowsNetwork: !page.isEphemeral)
                Text(pageTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(isOn ? 0.1 : 0.04)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Parsec leerá esta pestaña al responder" : "Preguntar sobre la pestaña abierta en Parsec")
        .accessibilityLabel("Usar pestaña actual: \(pageTitle)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
