import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LittleBrowserView: View {
    @Bindable var model: LittleWindowModel

    var body: some View {
        VStack(spacing: 0) {
            LittleToolbar(model: model)
            ZStack(alignment: .top) {
                WebViewHost(webView: model.page.webView, cornerRadius: Radius.card)
                LoadingLineView(page: model.page)
            }
            .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
            .padding(.horizontal, LittleWindowMetrics.contentInset)
            .padding(.bottom, LittleWindowMetrics.contentInset)
        }
        .background(VisualEffectBackground(material: .sidebar))
        .ignoresSafeArea()
    }
}

struct LittleToolbar: View {
    @Bindable var model: LittleWindowModel

    var body: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: LittleWindowMetrics.trafficLightsReservedWidth)
            IconButton(symbolName: "arrow.left", label: "Atrás (⌘[)", isEnabled: model.page.canGoBack) { model.page.webView.goBack() }
            IconButton(symbolName: "arrow.right", label: "Adelante (⌘])", isEnabled: model.page.canGoForward) { model.page.webView.goForward() }
            IconButton(symbolName: "arrow.clockwise", label: "Recargar (⌘R)") { model.page.webView.reload() }
            LittleAddressField(page: model.page)
            IconButton(symbolName: "link", label: "Copiar URL", isEnabled: model.page.currentURL != nil) {
                model.page.currentURL.map { Clipboard.copy($0.absoluteString) }
            }
            Button("Abrir en Parsec") { (model.window as? LittleWindow)?.promoteToTabAction(nil) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Abrir como pestaña (⌘O)")
        }
        .padding(.horizontal, 10)
        .frame(height: LittleWindowMetrics.toolbarHeight)
        .background(WindowDragArea())
    }
}

struct LittleAddressField: View {
    @Bindable var page: WebPage
    @ViewState private var isEditing = false
    @ViewState private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var displayText: String {
        (page.currentURL?.host() ?? page.currentHost).replacingOccurrences(of: WebConstants.wwwPrefix, with: "")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: page.currentURL?.scheme == WebConstants.httpsScheme ? "lock.fill" : "globe")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if isEditing {
                TextField("Buscar o escribir URL", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($isFocused)
                    .onSubmit(submit)
                    .onExitCommand { isEditing = false }
                    .onChange(of: isFocused) { _, isStillFocused in
                        if !isStillFocused { isEditing = false }
                    }
            } else {
                Text(displayText.isEmpty ? "Buscar o escribir URL" : displayText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(displayText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(SidebarPalette.controlFill(colorScheme, isActive: isEditing)))
        .contentShape(Rectangle())
        .onTapGesture(perform: beginEditing)
        .accessibilityLabel("Dirección: \(displayText)")
    }

    private func beginEditing() {
        guard !isEditing else { return }
        text = page.currentURL?.absoluteString ?? ""
        isEditing = true
        isFocused = true
    }

    private func submit() {
        isEditing = false
        guard let url = InputResolver.destination(for: text) else { return }
        page.load(url)
    }
}
