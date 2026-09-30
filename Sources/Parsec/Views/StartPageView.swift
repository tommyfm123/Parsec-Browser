import AppKit
import SwiftUI

enum StartMode: CaseIterable {
    case search
    case ask
    case browse

    var title: String {
        switch self {
        case .search: "Buscar"
        case .ask: "Preguntar"
        case .browse: "Agente"
        }
    }

    var symbolName: String {
        switch self {
        case .search: "magnifyingglass"
        case .ask: "questionmark.bubble"
        case .browse: "cursorarrow.motionlines"
        }
    }

    var placeholder: String {
        switch self {
        case .search: "Busca o escribe una dirección…"
        case .ask: "Pregunta lo que quieras…"
        case .browse: "Pídele al agente que navegue por ti…"
        }
    }

    var next: StartMode {
        let modes = Self.allCases
        return modes[((modes.firstIndex(of: self) ?? 0) + 1) % modes.count]
    }
}

struct StartPageView: View {
    private static let cardWidth: CGFloat = 640

    @Bindable var model: WindowModel
    let cornerRadius: CGFloat
    var targetNodeID: UUID?
    @ViewState private var query = ""
    @ViewState private var mode = StartMode.search
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            PageSurface(cornerRadius: cornerRadius)
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 48) {
                        VStack(spacing: 18) {
                            if let mark = BrandMark.image {
                                Image(nsImage: mark)
                                    .resizable()
                                    .renderingMode(.template)
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(.primary)
                                    .accessibilityHidden(true)
                            }
                            Text("¿Qué quieres saber hoy?")
                                .font(.system(size: 40, weight: .regular, design: .serif))
                                .tracking(-0.9)
                                .multilineTextAlignment(.center)
                        }
                        AskInputCard(model: model, query: $query, mode: $mode, isFocused: $isFieldFocused, isRunning: false, onSubmit: submit, onStop: {})
                            .frame(maxWidth: Self.cardWidth)
                        if !model.isPrivate {
                            StartPageLibrary(model: model, targetNodeID: targetNodeID)
                                .frame(maxWidth: Self.cardWidth)
                        }
                    }
                    .frame(maxWidth: 850)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .padding(.horizontal, 32)
                    .padding(.top, 56)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(cornerRadius > 0 ? 0 : SidebarView.outerInset)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 2)
        .task { focusInput() }
        .onChange(of: model.selectedSpaceID) { focusInput() }
    }

    private func focusInput() {
        model.window?.makeFirstResponder(nil)
        isFieldFocused = true
    }

    private func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        query = ""
        switch mode {
        case .search:
            guard let url = InputResolver.destination(for: text) else { return }
            guard let targetNodeID else { return _ = model.openInNewTab(url) }
            model.open(url, mode: .navigate(nodeID: targetNodeID))
        case .ask, .browse:
            model.startConversation(text, browsing: mode == .browse, in: targetNodeID)
        }
    }
}

struct PageSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
    }
}

struct AskInputCard: View {
    private static let startDictationSelector = Selector(("startDictation:"))

    @Bindable var model: WindowModel
    @Binding var query: String
    @Binding var mode: StartMode
    var isFocused: FocusState<Bool>.Binding
    let isRunning: Bool
    let onSubmit: () -> Void
    let onStop: () -> Void
    var attachTarget: AssistantModel?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(mode.placeholder, text: $query, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...6)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .onKeyPress(.tab) {
                    withAnimation(.snappy) { mode = mode.next }
                    return .handled
                }
            HStack(spacing: 8) {
                if mode != .search {
                    StartCircleButton(symbolName: "plus", label: "Adjuntar archivos", isProminent: false) {
                        (attachTarget ?? model.assistant).attachFiles()
                    }
                }
                StartModePicker(mode: $mode)
                Spacer(minLength: 8)
                if mode != .search {
                    ModelPicker()
                        .transition(.opacity)
                }
                StartCircleButton(symbolName: "mic", label: "Dictar", isProminent: false, action: startDictation)
                if isRunning {
                    StartCircleButton(symbolName: "stop.fill", label: "Detener", isProminent: true, action: onStop)
                } else {
                    StartCircleButton(symbolName: "arrow.up", label: "Enviar", isProminent: true, action: onSubmit)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(isFocused.wrappedValue ? 0.16 : 0.09)))
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 25, style: .continuous).fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035)))
        .animation(.snappy, value: mode)
    }

    private func startDictation() {
        isFocused.wrappedValue = true
        NSApp.sendAction(Self.startDictationSelector, to: nil, from: nil)
    }
}

struct ConversationPageView: View {
    private static let columnWidth: CGFloat = 720

    @Bindable var model: WindowModel
    @Bindable var conversation: AssistantModel
    let cornerRadius: CGFloat
    @ViewState private var query = ""
    @ViewState private var mode = StartMode.ask
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            PageSurface(cornerRadius: cornerRadius)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                            if message.role == .user {
                                ConversationQuestion(text: message.text, isFirst: index == 0)
                            } else {
                                AgentMessageView(model: model, assistant: conversation, message: message, textSize: 15)
                            }
                        }
                        Color.clear.frame(height: 150).id(Self.bottomAnchor)
                    }
                    .frame(maxWidth: Self.columnWidth, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 48)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .onChange(of: conversation.messages.last?.text) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                .onChange(of: conversation.messages.count) { withAnimation(.snappy) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) } }
            }
            AskInputCard(model: model, query: $query, mode: $mode, isFocused: $isFieldFocused, isRunning: conversation.isRunning, onSubmit: submit, onStop: conversation.stop, attachTarget: conversation)
                .frame(maxWidth: Self.columnWidth)
                .padding(.horizontal, 32)
                .padding(.bottom, 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .padding(cornerRadius > 0 ? 0 : SidebarView.outerInset)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 2)
        .onAppear { isFieldFocused = true }
    }

    private static let bottomAnchor = "conversation-bottom"

    private func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !conversation.isRunning else { return }
        query = ""
        switch mode {
        case .search:
            guard let url = InputResolver.destination(for: text) else { return }
            _ = model.openInNewTab(url)
        case .ask:
            conversation.send(text)
        case .browse:
            conversation.browse(text)
        }
    }
}

struct ConversationQuestion: View {
    let text: String
    let isFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !isFirst {
                Divider().padding(.top, 14)
            }
            Text(text)
                .font(.system(size: isFirst ? 30 : 24, weight: .regular, design: .serif))
                .tracking(-0.5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StartModePicker: View {
    @Binding var mode: StartMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StartMode.allCases, id: \.self) { candidate in
                Button { withAnimation(.snappy) { mode = candidate } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: candidate.symbolName).font(.system(size: 11, weight: .semibold))
                        Text(candidate.title).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(candidate == mode ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(candidate == mode ? Color(nsColor: .textBackgroundColor) : Color.clear).shadow(color: .black.opacity(candidate == mode ? 0.12 : 0), radius: 2, y: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .clickable()
                .help(candidate.title)
                .accessibilityLabel(candidate.title)
                .accessibilityAddTraits(candidate == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

struct StartCircleButton: View {
    let symbolName: String
    let label: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: isProminent ? 11 : 13, weight: isProminent ? .bold : .medium))
                .foregroundStyle(isProminent ? Color(nsColor: .textBackgroundColor) : Color.secondary)
                .frame(width: isProminent ? 26 : 30, height: isProminent ? 26 : 30)
                .background(Circle().fill(isProminent ? Color.primary : Color.clear))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 15)
        .help(label)
        .accessibilityLabel(label)
    }
}
