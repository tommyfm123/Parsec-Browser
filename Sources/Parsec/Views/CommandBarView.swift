import SwiftUI

struct CommandBarView: View {
    private static let fieldHeight: CGFloat = 60
    private static let resultsMaxHeight: CGFloat = 380
    private static let nominalHeight = fieldHeight + resultsMaxHeight
    private static let radius: CGFloat = 24

    @Bindable var model: WindowModel
    @Bindable var commandBar: CommandBarModel
    @FocusState private var isFieldFocused: Bool
    @ViewState private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var placeholder: String {
        switch commandBar.mode {
        case .newTab: "Busca, escribe una dirección o pregunta algo"
        case .navigateCurrent, .navigate: "Ir a…"
        }
    }

    private var canAsk: Bool {
        !model.isPrivate && !commandBar.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ZStack {
                    VisualEffectBackground(material: .fullScreenUI, blendingMode: .withinWindow)
                    Color.black.opacity(0.12)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.dismissCommandBar() }
                panel
                    .padding(.top, max(40, (geometry.size.height - Self.nominalHeight) / 2))
                    .scaleEffect(isVisible || reduceMotion ? 1 : 0.97)
                    .opacity(isVisible ? 1 : 0)
            }
        }
        .onAppear {
            isFieldFocused = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isVisible = true }
        }
        .task { isFieldFocused = true }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            field
            if !commandBar.results.isEmpty {
                Divider().opacity(0.4)
                results
            }
            CommandBarFooter(canAsk: canAsk, assistantName: BrowserStore.shared.settings.assistantProvider.assistantName) {
                model.dismissCommandBar()
                AppDelegate.shared.openSettings(section: .shortcuts)
            }
        }
        .frame(width: LayoutConstants.commandBarWidth)
        .liquidGlass(in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 50, y: 20)
        .animation(.snappy(duration: 0.2), value: commandBar.results.count)
    }

    private var field: some View {
        HStack(spacing: 12) {
            Group {
                if let mark = BrandMark.image {
                    Image(nsImage: mark).resizable().renderingMode(.template).interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "magnifyingglass").resizable().scaledToFit()
                }
            }
            .frame(width: 20, height: 20)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            TextField(placeholder, text: $commandBar.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .regular))
                .focused($isFieldFocused)
                .onSubmit { commandBar.activateSelection() }
                .onKeyPress(.upArrow) {
                    commandBar.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    commandBar.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard canAsk else { return .ignored }
                    commandBar.askAssistantWithQuery()
                    return .handled
                }
                .onExitCommand { model.dismissCommandBar() }
            if !commandBar.query.isEmpty {
                Button { commandBar.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .clickable()
                .accessibilityLabel("Borrar")
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Self.fieldHeight)
        .animation(.snappy(duration: 0.15), value: commandBar.query.isEmpty)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(commandBar.results.enumerated()), id: \.element.id) { index, result in
                        if let section = result.section, section != commandBar.results[safe: index - 1]?.section {
                            Text(section)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, index == 0 ? 4 : 10)
                                .padding(.bottom, 4)
                        }
                        Button { commandBar.activate(result) } label: {
                            CommandResultRow(result: result, isSelected: index == commandBar.selectedIndex)
                            }
                            .buttonStyle(.plain)
                            .id(result.id)
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: Self.resultsMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: commandBar.selectedIndex) { _, index in
                guard let result = commandBar.results[safe: index] else { return }
                proxy.scrollTo(result.id)
            }
        }
    }
}

struct CommandBarFooter: View {
    let canAsk: Bool
    let assistantName: String
    let onCustomize: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            KeyHint(keys: "↑↓", label: "navegar")
            KeyHint(keys: "↩", label: "abrir")
            if canAsk {
                KeyHint(keys: "⇥", label: "preguntar a \(assistantName)")
                    .transition(.opacity)
            }
            Spacer()
            KeyHint(keys: "esc", label: "cerrar")
            Button(action: onCustomize) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .hoverHighlight(cornerRadius: 6)
            }
            .buttonStyle(.plain)
            .help("Personalizar lo que aparece aquí")
            .accessibilityLabel("Personalizar la barra de comandos")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 34)
        .background(Color.primary.opacity(0.03))
        .animation(.snappy(duration: 0.15), value: canAsk)
    }
}

struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 17)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            Text(label).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct CommandResultRow: View {
    let result: CommandResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if let iconURL = result.iconURL {
                    FaviconView(url: iconURL, size: 16)
                } else {
                    Image(systemName: result.symbolName).font(.system(size: 13, weight: .medium))
                }
            }
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(isSelected ? 0.1 : 0.05)))
            Text(result.title)
                .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(result.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "return")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(isSelected ? 0.09 : 0)))
        .contentShape(Rectangle())
        .clickable()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PeekView: View {
    @Bindable var model: WindowModel
    @Bindable var node: SidebarNode

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closePeek() }
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        FaviconView(url: node.liveURL, size: 14, allowsNetwork: node.allowsFaviconNetwork)
                        Text(node.page?.title.isEmpty == false ? node.displayTitle : node.displayHost)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Button("Abrir como pestaña  ⌘O") { model.promotePeek() }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12))
                        IconButton(symbolName: "xmark", label: "Cerrar (Esc)") { model.closePeek() }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(.regularMaterial)
                    ZStack(alignment: .top) {
                        if let page = node.page {
                            WebViewHost(webView: page.webView)
                        }
                        LoadingLineView(page: node.page)
                    }
                }
                .frame(width: geometry.size.width * LayoutConstants.peekScale, height: geometry.size.height * LayoutConstants.peekScale)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
            }
        }
    }
}
