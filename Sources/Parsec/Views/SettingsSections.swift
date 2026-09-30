import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case aboutYou = "Sobre ti"
    case profiles = "Perfiles"
    case spaces = "Spaces"
    case assistant = "IA"
    case shortcuts = "Atajos"
    case privacy = "Privacidad"
    case passwords = "Contraseñas"
    case documents = "Documentos"
    case advanced = "Avanzado"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .aboutYou: "person.text.rectangle"
        case .profiles: "person.crop.circle"
        case .spaces: "square.stack"
        case .assistant: "sparkles"
        case .shortcuts: "keyboard"
        case .privacy: "lock.shield"
        case .passwords: "key"
        case .documents: "doc.text"
        case .advanced: "slider.horizontal.3"
        }
    }
}

struct SettingsView: View {
    static let size = CGSize(width: 740, height: 620)

    @ViewState private var selection: SettingsSection

    init(initialSection: SettingsSection = .general) {
        _selection = ViewState(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selection)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(selection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .general: GeneralSettings()
        case .aboutYou: AboutYouSettings()
        case .profiles: ProfileSettings()
        case .spaces: SpaceSettings()
        case .assistant: AssistantSettings()
        case .shortcuts: ShortcutSettings()
        case .privacy: PrivacySettings()
        case .passwords: PasswordSettings()
        case .documents: DocumentSettings()
        case .advanced: AdvancedSettings()
        }
    }
}

struct SettingsTabBar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(spacing: 8) {
            Text(selection.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .frame(height: 28)
            HStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    Button { selection = section } label: {
                        VStack(spacing: 3) {
                            Image(systemName: section.symbolName)
                                .font(.system(size: 17, weight: .regular))
                                .frame(height: 22)
                            Text(section.rawValue).font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(selection == section ? Color.accentColor : Color.secondary)
                        .frame(width: 68, height: 50)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(selection == section ? 0.07 : 0)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(WindowDragArea())
    }
}

struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                        subview
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                        if index < subviews.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsItem<Accessory: View>: View {
    let symbolName: String
    let tint: Color
    let title: String
    var detail: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

struct SettingsToggle: View {
    let symbolName: String
    let tint: Color
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsItem(symbolName: symbolName, tint: tint, title: title, detail: detail) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

@MainActor
enum SettingsBinding {
    static func make<Value>(_ keyPath: WritableKeyPath<BrowserSettings, Value>) -> Binding<Value> {
        Binding(
            get: { BrowserStore.shared.settings[keyPath: keyPath] },
            set: { newValue in
                BrowserStore.shared.settings[keyPath: keyPath] = newValue
                BrowserStore.shared.saveSoon()
            }
        )
    }
}

struct SettingsStatus: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary)
    }
}

struct GeneralSettings: View {
    @ViewState private var statusMessage = ""
    private var store: BrowserStore { BrowserStore.shared }

    private var downloadFolderName: String {
        DownloadManager.downloadFolderURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    var body: some View {
        SettingsGroup(title: "Diseño") {
            SettingsItem(symbolName: "sidebar.left", tint: .blue, title: "Pestañas", detail: "Sidebar vertical o barra arriba, como Chrome.") {
                ParsecSegmented(selection: SettingsBinding.make(\.layout), options: [(SidebarLayout.sidebar, "Sidebar"), (SidebarLayout.topTabs, "Arriba")])
            }
            SettingsToggle(symbolName: "magnifyingglass", tint: .gray, title: "Sugerencias de Google", detail: "Lo que escribes en la command bar se envía a Google.", isOn: SettingsBinding.make(\.showsSearchSuggestions))
        }
        SettingsGroup(title: "Navegador") {
            SettingsItem(symbolName: "safari", tint: .indigo, title: "Navegador predeterminado", detail: "Abrir en Parsec los links de otras apps.") {
                Button("Usar Parsec") { AppDelegate.shared.setAsDefaultBrowser() }
            }
            SettingsItem(symbolName: "arrow.down.circle", tint: .teal, title: "Carpeta de descargas", detail: downloadFolderName) {
                HStack(spacing: 6) {
                    Button("Mostrar") { NSWorkspace.shared.open(DownloadManager.downloadFolderURL) }
                    Button("Cambiar…") { chooseDownloadFolder() }
                }
            }
        }
        SettingsGroup(title: "Parsec") {
            SettingsToggle(symbolName: "arrow.counterclockwise", tint: .green, title: "Restaurar la sesión anterior", detail: "Al abrir Parsec, recupera la ventana, las pestañas de hoy y la pestaña que tenías abierta. Se aplica al próximo inicio.", isOn: SettingsBinding.make(\.restoresPreviousSession))
            SettingsToggle(symbolName: "power", tint: .red, title: "Confirmar antes de salir", detail: "Pregunta antes de cerrar Parsec por completo.", isOn: SettingsBinding.make(\.confirmsBeforeQuit))
            SettingsItem(symbolName: "sparkles", tint: .purple, title: "Bienvenida", detail: "La presentación de Parsec, con sonido.") {
                Button("Reproducir") { AppDelegate.shared.replayWelcome() }
            }
            SettingsItem(symbolName: "square.and.arrow.down", tint: .orange, title: "Importar desde Arc", detail: "Spaces, favoritos, fijadas, carpetas y colores.") {
                Button("Importar") { importFromArc() }.disabled(!ArcImporter.isAvailable)
            }
        }
        if !statusMessage.isEmpty { SettingsStatus(message: statusMessage) }
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = DownloadManager.downloadFolderURL
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        store.settings.downloadFolderPath = folderURL.path
        store.saveSoon()
    }

    private func importFromArc() {
        do {
            try store.importFromArc()
            statusMessage = "Sidebar de Arc importado"
        } catch {
            statusMessage = "No se pudo leer el sidebar de Arc: \(error.localizedDescription)"
        }
    }
}

struct AboutYouSettings: View {
    private static let multilineLimit = 3...8

    private var profile: Binding<UserProfile> { SettingsBinding.make(\.userProfile) }

    private var initials: String {
        let letters = profile.wrappedValue.name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "" : String(letters).uppercased()
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                if initials.isEmpty {
                    Image(systemName: "person.fill").font(.system(size: 24)).foregroundStyle(.white)
                } else {
                    Text(initials).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                }
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.wrappedValue.name.isEmpty ? "Tu perfil" : profile.wrappedValue.name).font(.system(size: 18, weight: .semibold))
                Text("Parsec y la IA te conocen por lo que escribas aquí. Todo queda guardado solo en tu Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
        SettingsGroup(title: "Datos personales") {
            ProfileField(symbolName: "person.fill", tint: .blue, title: "Nombre", prompt: "Cómo quieres que te llamen", text: profile.name)
            ProfileField(symbolName: "briefcase.fill", tint: .brown, title: "A qué te dedicas", prompt: "Ej.: fundador de una startup de software", text: profile.occupation)
            ProfileField(symbolName: "mappin.and.ellipse", tint: .red, title: "Dónde vives", prompt: "Ciudad y país", text: profile.location)
            ProfileField(symbolName: "globe", tint: .teal, title: "Idiomas", prompt: "Ej.: español, inglés", text: profile.languages)
        }
        SettingsGroup(title: "Sobre ti", footer: "Tus intereses, proyectos, empresas o cualquier contexto útil.") {
            TextField("Cuéntale a la IA sobre ti…", text: profile.about, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(Self.multilineLimit)
        }
        SettingsGroup(title: "Instrucciones para la IA", footer: "Cómo quieres que te responda: tono, formato, largo, idioma.") {
            TextField("Ej.: respóndeme corto, directo y con ejemplos", text: profile.assistantInstructions, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(Self.multilineLimit)
        }
        SettingsGroup(footer: "Si lo apagas, la IA no recibe nada de este perfil; solo se usa tu nombre en el saludo.") {
            SettingsToggle(symbolName: "sparkles", tint: .purple, title: "Compartir mi perfil con la IA", detail: "Se envía al proveedor que elijas junto con cada pedido.", isOn: profile.sharesWithAssistant)
        }
    }
}

struct ProfileField: View {
    let symbolName: String
    let tint: Color
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        SettingsItem(symbolName: symbolName, tint: tint, title: title) {
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13))
                .frame(width: 280)
        }
    }
}

struct ProfileSettings: View {
    private var store: BrowserStore { BrowserStore.shared }

    var body: some View {
        ForEach(store.profiles) { profile in
            ProfileSettingsCard(profile: profile)
        }
        Button { _ = store.addProfile(name: "Perfil \(store.profiles.count + 1)") } label: {
            Label("Nuevo perfil", systemImage: "plus")
        }
    }
}

struct ProfileSettingsCard: View {
    private static let archiveOptions = [12, 24, 24 * 7, 24 * 30]

    @Bindable var profile: Profile
    @ViewState private var statusMessage = ""
    @ViewState private var isIconPickerPresented = false
    private var store: BrowserStore { BrowserStore.shared }

    private var profileColor: Binding<Color> {
        Binding(get: { profile.accentColor?.color ?? .blue }, set: { profile.accentColor = ThemeColor($0); store.saveSoon() })
    }

    private var archiveHours: Binding<Int> {
        Binding(get: { profile.archiveAfterHours ?? Profile.defaultArchiveHours }, set: { profile.archiveAfterHours = $0; store.saveSoon() })
    }

    var body: some View {
        SettingsGroup(footer: statusMessage.isEmpty ? nil : statusMessage) {
            HStack(spacing: 12) {
                Button { isIconPickerPresented = true } label: {
                    Image(systemName: profile.iconSymbol ?? "person.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(profileColor.wrappedValue.gradient))
                }
                .buttonStyle(.plain)
                .help("Cambiar icono")
                .popover(isPresented: $isIconPickerPresented) {
                    SymbolPicker(title: profile.name, selectedSymbol: profile.iconSymbol, preview: AnyView(EmptyView())) { symbol in
                        profile.iconSymbol = symbol
                        store.saveSoon()
                        isIconPickerPresented = false
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Nombre", text: $profile.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .onSubmit { store.saveSoon() }
                    Text("\(store.spaceIDs(usingProfile: profile.id).count) Spaces · logins y cookies propios")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProfileColorSwatches(selection: Binding(get: { profile.accentColor }, set: { profile.accentColor = $0; store.saveSoon() }))
            }
            SettingsItem(symbolName: "archivebox", tint: .brown, title: "Archivar pestañas de hoy", detail: "Las pestañas sin fijar se cierran solas después de este tiempo.") {
                ParsecSelect(selection: archiveHours, options: Self.archiveOptions.map { ($0, Self.label(forHours: $0)) }, width: 120)
            }
            SettingsItem(symbolName: "clock.arrow.circlepath", tint: .gray, title: "Historial", detail: "Lo que aparece en la command bar y en Seguir donde lo dejaste.") {
                Button("Limpiar") { clearHistory() }
            }
            SettingsItem(symbolName: "externaldrive", tint: .red, title: "Datos de sitios", detail: "Cookies, sesiones y caché. Tendrás que volver a iniciar sesión.") {
                Button("Borrar…") { clearWebsiteData() }
            }
        }
    }

    static func label(forHours hours: Int) -> String {
        switch hours {
        case 12: "12 horas"
        case 24: "24 horas"
        case 24 * 7: "7 días"
        default: "30 días"
        }
    }

    private func clearHistory() {
        store.history.clear(profileID: profile.id)
        statusMessage = "Historial de \(profile.name) borrado"
    }

    private func clearWebsiteData() {
        let alert = NSAlert()
        alert.messageText = "¿Borrar cookies y sesiones de \(profile.name)?"
        alert.informativeText = "Vas a tener que volver a iniciar sesión en los sitios de este perfil."
        alert.addButton(withTitle: "Borrar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let profileID = profile.id
        Task {
            await WebConfigurationFactory.deleteData(profileID: profileID)
            statusMessage = "Datos de sitios de \(profile.name) borrados"
        }
    }
}

struct ProfileColorSwatches: View {
    private static let palette = [
        ThemeColor(red: 0.2, green: 0.47, blue: 1), ThemeColor(red: 0.55, green: 0.36, blue: 0.96), ThemeColor(red: 0.93, green: 0.33, blue: 0.6),
        ThemeColor(red: 0.95, green: 0.32, blue: 0.3), ThemeColor(red: 0.98, green: 0.58, blue: 0.2), ThemeColor(red: 0.2, green: 0.72, blue: 0.45),
        ThemeColor(red: 0.18, green: 0.68, blue: 0.75), ThemeColor(red: 0.45, green: 0.47, blue: 0.5),
    ]

    @Binding var selection: ThemeColor?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.palette, id: \.self) { color in
                Button { selection = color } label: {
                    Circle()
                        .fill(color.color.gradient)
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selection == color ? 0.5 : 0), lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .clickable()
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}

struct SpaceSettings: View {
    private var store: BrowserStore { BrowserStore.shared }

    var body: some View {
        SettingsGroup(footer: "El perfil define qué logins y cookies usa cada Space.") {
            ForEach(store.spaces) { space in
                SpaceSettingsRow(space: space)
            }
        }
    }
}

struct SpaceSettingsRow: View {
    @Bindable var space: Space
    @ViewState private var isThemeEditorPresented = false
    private var store: BrowserStore { BrowserStore.shared }

    var body: some View {
        HStack(spacing: 12) {
            Button { isThemeEditorPresented = true } label: {
                SpaceBackgroundView(theme: space.theme)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(Image(systemName: space.iconSymbol ?? "circle.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.primary.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help("Editar tema")
            .popover(isPresented: $isThemeEditorPresented) { ArcThemeEditor(space: space) }
            TextField("Nombre", text: $space.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { store.saveSoon() }
            ParsecSelect(selection: Binding(get: { space.profileID }, set: { SpaceProfiles.assign($0, to: space) }), options: store.profiles.map { ($0.id, $0.name) }, width: 140)
            Button("Tema…") { isThemeEditorPresented = true }
        }
    }
}

@MainActor
@Observable
final class ProviderStatusModel {
    enum TestState: Equatable {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    private static let testPrompt = "Responde únicamente: Conectado"
    private static let testSystemPrompt = "Responde en una sola palabra."

    var testState = TestState.idle
    @ObservationIgnored private var run: AssistantRun?

    func isReady(_ provider: AssistantProviderKind) -> Bool {
        ModelCatalog.isAvailable(provider)
    }

    func statusText(_ provider: AssistantProviderKind) -> String {
        switch provider {
        case .claudeCode, .codexCLI: isReady(provider) ? "Instalado en tu Mac" : "No instalado"
        case .anthropicAPI, .openAIAPI: isReady(provider) ? "API key guardada en el Llavero" : "Falta la API key"
        case .localModels: LocalModels.shared.isServerRunning ? "Ollama activo · \(LocalModels.shared.installed.count) modelos" : "Ollama no está abierto"
        case .customAPI: BrowserStore.shared.settings.customProviderBaseURL
        }
    }

    func test(_ provider: AssistantProviderKind) {
        testState = .running
        let request = AssistantRequest(
            prompt: Self.testPrompt, history: [], attachments: [], systemPrompt: Self.testSystemPrompt,
            usesWebSearch: false, enabledConnectors: [], resumeSessionID: nil,
            model: BrowserStore.shared.settings.assistantModel(for: provider)
        )
        run = AssistantProviderFactory.start(provider, request: request) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: AssistantEvent) {
        switch event {
        case .finished(let text, _, let isError):
            testState = isError ? .failure(text) : .success(text.isEmpty ? "Conectado" : text)
            run = nil
        case .failed(let message):
            testState = .failure(message)
            run = nil
        case .textDelta, .toolStarted:
            break
        }
    }
}

struct AssistantSettings: View {
    @ViewState private var status = ProviderStatusModel()
    @ViewState private var apiKeyDraft = ""
    private var store: BrowserStore { BrowserStore.shared }
    private var provider: AssistantProviderKind { store.settings.assistantProvider }

    private var modelBinding: Binding<String> {
        Binding(
            get: { store.settings.assistantModel(for: provider) },
            set: { store.settings.assistantModels[provider.rawValue] = $0; store.saveSoon() }
        )
    }

    var body: some View {
        SettingsGroup(title: "Proveedor") {
            ForEach(AssistantProviderKind.allCases) { candidate in
                Button {
                    store.settings.assistantProvider = candidate
                    status.testState = .idle
                    apiKeyDraft = ""
                    store.saveSoon()
                } label: {
                    HStack(spacing: 12) {
                        ProviderLogo(provider: candidate, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidate.displayName).font(.system(size: 13, weight: .medium))
                            Text(status.statusText(candidate)).font(.system(size: 11)).foregroundStyle(status.isReady(candidate) ? Color.green : Color.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: candidate == provider ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(candidate == provider ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        SettingsGroup(title: "Configuración de \(provider.displayName)", footer: provider.detail) {
            if provider == .customAPI {
                SettingsItem(symbolName: "textformat", tint: .gray, title: "Nombre") {
                    TextField("Mi IA", text: SettingsBinding.make(\.customProviderName)).textFieldStyle(.roundedBorder).frame(width: 220)
                }
                SettingsItem(symbolName: "link", tint: .blue, title: "URL base", detail: "Termina en /v1") {
                    TextField("http://localhost:11434/v1", text: SettingsBinding.make(\.customProviderBaseURL)).textFieldStyle(.roundedBorder).frame(width: 220)
                }
            }
            if provider.acceptsAPIKey {
                SettingsItem(symbolName: "key.fill", tint: .orange, title: "API key", detail: provider.needsAPIKey ? "Se guarda cifrada en el Llavero." : "Opcional. Se guarda cifrada en el Llavero.") {
                    HStack(spacing: 6) {
                        SecureField(APIKeyStore.hasKey(for: provider) ? "••••••••••" : "Pega tu API key", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Button("Guardar") {
                            APIKeyStore.save(apiKeyDraft, for: provider)
                            apiKeyDraft = ""
                        }
                        .disabled(apiKeyDraft.isEmpty)
                    }
                }
            }
            SettingsItem(symbolName: "cpu", tint: .purple, title: "Modelo", detail: provider.defaultModel.isEmpty ? "Vacío usa el de tu cuenta." : nil) {
                if provider == .localModels {
                    ParsecSelect(selection: modelBinding, options: LocalModels.shared.installed.map { ($0, $0) }, width: 220)
                } else {
                    TextField(provider.defaultModel.isEmpty ? "Por defecto" : provider.defaultModel, text: modelBinding).textFieldStyle(.roundedBorder).frame(width: 220)
                }
            }
            SettingsItem(symbolName: "bolt.horizontal", tint: .green, title: "Conexión") {
                HStack(spacing: 8) {
                    testResult
                    Button("Probar") { status.test(provider) }.disabled(status.testState == .running)
                }
            }
        }
        LocalModelSettings()
        SettingsGroup(title: "Agente que navega", footer: "Apagado, el agente navega en un perfil temporal sin tus cookies ni sesiones, que se borra al terminar. Siempre te pide permiso antes de enviar un formulario.") {
            SettingsToggle(symbolName: "person.badge.key.fill", tint: .orange, title: "Usar mis sesiones iniciadas", detail: "Permite que el agente entre a sitios donde ya iniciaste sesión.", isOn: SettingsBinding.make(\.agentUsesSessions))
        }
        SettingsGroup(title: "Agente") {
            SettingsToggle(symbolName: "doc.text", tint: .blue, title: "Incluir la pestaña actual", detail: "El agente recibe el texto de la página como contexto.", isOn: SettingsBinding.make(\.assistantIncludesPage))
            SettingsToggle(symbolName: "globe", tint: .teal, title: "Búsqueda web", detail: "Disponible con Claude Code y la API de Anthropic.", isOn: SettingsBinding.make(\.assistantUsesWebSearch))
            SettingsItem(symbolName: "command", tint: .gray, title: "Abrir el panel", detail: "O lleva el mouse al borde derecho de la ventana.") {
                Text("⌘J").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch status.testState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .success(let text):
            Label(text, systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green).lineLimit(1)
        case .failure(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).frame(maxWidth: 240)
        }
    }
}

struct LocalModelSettings: View {
    private var localModels: LocalModels { LocalModels.shared }

    var body: some View {
        SettingsGroup(title: "Modelos locales", footer: localModels.errorMessage ?? "Corren en tu Mac con Ollama: nada sale de tu computadora.") {
            if !localModels.isServerRunning {
                SettingsItem(symbolName: "shippingbox.fill", tint: .black, title: "Instala Ollama", detail: "Ábrelo y vuelve aquí para descargar modelos.") {
                    HStack(spacing: 6) {
                        Button("Descargar Ollama") { NSWorkspace.shared.open(LocalModels.downloadURL) }
                        Button("Reintentar") { Task { await localModels.refresh() } }
                    }
                }
            }
            ForEach(localModels.installed, id: \.self) { name in
                SettingsItem(symbolName: "cpu.fill", tint: .green, title: name, detail: "Instalado") {
                    Button("Eliminar", role: .destructive) { localModels.remove(name) }
                }
            }
            ForEach(LocalModels.suggestions.filter { !localModels.isInstalled($0.name) }) { suggestion in
                SettingsItem(symbolName: "arrow.down.circle.fill", tint: .blue, title: suggestion.name, detail: suggestion.detail) {
                    if let progress = localModels.downloadProgress[suggestion.name] {
                        ProgressView(value: progress).frame(width: 110)
                    } else {
                        Button("Descargar") { localModels.download(suggestion.name) }.disabled(!localModels.isServerRunning)
                    }
                }
            }
        }
        .task { await localModels.refresh() }
    }
}

struct CommandBarSettings: View {
    private var store: BrowserStore { BrowserStore.shared }
    private var enabled: [QuickAction] { store.settings.commandBarActions }
    private var disabled: [QuickAction] { QuickAction.allCases.filter { !enabled.contains($0) } }

    var body: some View {
        SettingsGroup(title: "Barra de comandos (⌘T)", footer: "Lo que ves antes de escribir. Al escribir, primero aparece buscar y después la IA.") {
            SettingsToggle(symbolName: "star.fill", tint: .yellow, title: "Favoritos", detail: "Los favoritos del sidebar.", isOn: SettingsBinding.make(\.commandBarShowsFavorites))
            SettingsToggle(symbolName: "clock.fill", tint: .blue, title: "Pestañas recientes", detail: "Las últimas que usaste en este Space.", isOn: SettingsBinding.make(\.commandBarShowsRecentTabs))
            SettingsToggle(symbolName: "bubble.left.and.text.bubble.right.fill", tint: .purple, title: "Conversaciones recientes", detail: "Tus últimas charlas con la IA.", isOn: SettingsBinding.make(\.commandBarShowsConversations))
        }
        SettingsGroup(title: "Acciones rápidas", footer: "Ordénalas con las flechas. Las desactivadas siguen disponibles al escribir.") {
            ForEach(Array(enabled.enumerated()), id: \.element) { index, action in
                QuickActionRow(action: action, isEnabled: true) {
                    HStack(spacing: 2) {
                        IconButton(symbolName: "chevron.up", label: "Subir", isEnabled: index > 0) { move(action, by: -1) }
                        IconButton(symbolName: "chevron.down", label: "Bajar", isEnabled: index < enabled.count - 1) { move(action, by: 1) }
                    }
                } onToggle: { toggle(action) }
            }
            ForEach(disabled, id: \.self) { action in
                QuickActionRow(action: action, isEnabled: false) { EmptyView() } onToggle: { toggle(action) }
            }
        }
        Button("Restablecer la barra de comandos") {
            store.settings.commandBarActions = QuickAction.defaults
            store.saveSoon()
        }
        .clickable()
    }

    private func toggle(_ action: QuickAction) {
        if enabled.contains(action) {
            store.settings.commandBarActions.removeAll { $0 == action }
        } else {
            store.settings.commandBarActions.append(action)
        }
        store.saveSoon()
    }

    private func move(_ action: QuickAction, by offset: Int) {
        guard let index = enabled.firstIndex(of: action), enabled.indices.contains(index + offset) else { return }
        store.settings.commandBarActions.swapAt(index, index + offset)
        store.saveSoon()
    }
}

struct QuickActionRow<Controls: View>: View {
    let action: QuickAction
    let isEnabled: Bool
    @ViewBuilder let controls: Controls
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
            Text(action.title)
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            Spacer()
            controls
            Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

struct ShortcutSettings: View {
    @ViewState private var revision = 0
    private var store: BrowserStore { BrowserStore.shared }

    var body: some View {
        CommandBarSettings()
        ForEach(MainMenu.configurableSections, id: \.title) { section in
            SettingsGroup(title: section.title) {
                ForEach(section.items) { item in
                    HStack {
                        Text(item.title).font(.system(size: 13))
                        Spacer()
                        ShortcutRecorder(item: item) { revision += 1 }
                    }
                }
            }
        }
        Button("Restablecer todos los atajos") {
            store.settings.shortcutOverrides = [:]
            store.saveSoon()
            NSApp.mainMenu = MainMenu.build()
            revision += 1
        }
        .id(revision)
    }
}

struct ShortcutRecorder: View {
    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51
    private static let recordableModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    private static let requiredModifiers: NSEvent.ModifierFlags = [.command, .option, .control]

    let item: MenuShortcutItem
    let onChange: () -> Void
    @ViewState private var isRecording = false
    @ViewState private var monitor: Any?

    private var displayText: String {
        let shortcut = MainMenu.shortcut(for: item)
        return ShortcutCode.display(key: shortcut.key, modifiers: shortcut.modifiers)
    }

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "Presiona las teclas…" : displayText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                .frame(minWidth: 90)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor.opacity(isRecording ? 0.8 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help("Clic para grabar. Esc cancela, borrar restablece.")
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        guard !isRecording else { return stopRecording() }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode { return stopRecording() }
        if event.keyCode == Self.deleteKeyCode { return save(nil) }
        let modifiers = event.modifierFlags.intersection(Self.recordableModifiers)
        guard !modifiers.isDisjoint(with: Self.requiredModifiers), let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return }
        save(ShortcutCode.encode(key: key, modifiers: modifiers))
    }

    private func save(_ code: String?) {
        BrowserStore.shared.settings.shortcutOverrides[item.id] = code
        BrowserStore.shared.saveSoon()
        NSApp.mainMenu = MainMenu.build()
        stopRecording()
        onChange()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

struct PrivacySettings: View {
    @ViewState private var newBlockedSite = ""
    @ViewState private var statusMessage = ""
    private var store: BrowserStore { BrowserStore.shared }

    var body: some View {
        SettingsGroup(title: "Protección", footer: "Cada pestaña corre en su propio proceso aislado de WebKit, con sandbox del sistema.") {
            SettingsItem(symbolName: "shield.lefthalf.filled", tint: .blue, title: "Bloqueo de anuncios y rastreadores", detail: "EasyList + EasyPrivacy, actualizadas cada semana.") { EnabledMark() }
            SettingsItem(symbolName: "lock.fill", tint: .green, title: "Solo HTTPS", detail: "Aviso claro antes de abrir un sitio sin cifrar.") { EnabledMark() }
            SettingsItem(symbolName: "hand.raised.fill", tint: .indigo, title: "Cookies de terceros bloqueadas", detail: "Regla propia de Parsec, siempre activa. Datos separados por perfil.") { EnabledMark() }
            SettingsToggle(symbolName: "exclamationmark.shield.fill", tint: .red, title: "Avisar de sitios fraudulentos", detail: "Phishing y malware, con Navegación segura. Se aplica a pestañas nuevas.", isOn: SettingsBinding.make(\.warnsAboutFraudulentSites))
            SettingsToggle(symbolName: "arrow.down.app.fill", tint: .orange, title: "Confirmar descargas de riesgo", detail: "Apps, instaladores y scripts. macOS los revisa con Gatekeeper al abrirlos.", isOn: SettingsBinding.make(\.warnsBeforeRiskyDownloads))
        }
        SettingsGroup(title: "Permisos de sitios", footer: "Las notificaciones web están desactivadas. El portapapeles solo se lee cuando pegas.") {
            if store.permissionEntries.isEmpty {
                Text("Ningún sitio pidió permisos todavía.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(store.permissionEntries) { entry in
                SettingsItem(symbolName: entry.isGranted ? "video.fill" : "video.slash.fill", tint: entry.isGranted ? .green : .gray, title: entry.host, detail: "\(entry.isGranted ? "Permitido" : "Bloqueado"): \(entry.kind.label)") {
                    Button("Revocar") { store.removePermission(entry) }
                }
            }
        }
        SettingsGroup(title: "Datos de navegación", footer: statusMessage.isEmpty ? nil : statusMessage) {
            SettingsItem(symbolName: "clock.arrow.circlepath", tint: .gray, title: "Historial", detail: "De todos los perfiles.") {
                Button("Borrar") { clearHistory() }
            }
            SettingsItem(symbolName: "internaldrive", tint: .teal, title: "Caché", detail: "Libera espacio sin cerrar sesiones.") {
                Button("Vaciar") { clearCaches() }
            }
            SettingsItem(symbolName: "externaldrive.fill.badge.xmark", tint: .red, title: "Cookies y sesiones", detail: "De todos los perfiles. Tendrás que volver a iniciar sesión.") {
                Button("Borrar…", role: .destructive) { clearAllWebsiteData() }
            }
        }
        SettingsGroup(title: "Conversaciones con la IA", footer: "Se guardan solo en tu Mac, nunca las de ventanas privadas. Ábrelas con ⌘Y.") {
            SettingsToggle(symbolName: "bubble.left.and.text.bubble.right.fill", tint: .purple, title: "Guardar historial de conversaciones", detail: "Para retomarlas cuando vuelvas a abrir Parsec.", isOn: SettingsBinding.make(\.savesConversations))
            SettingsItem(symbolName: "trash.fill", tint: .red, title: "Conversaciones guardadas", detail: "\(ConversationStore.shared.conversations.count) en total.") {
                Button("Borrar todo…", role: .destructive) { clearConversations() }
                    .disabled(ConversationStore.shared.conversations.isEmpty)
            }
        }
        SettingsGroup(title: "Sitios bloqueados", footer: "Estos sitios no se abren en ningún perfil. Incluye sus subdominios.") {
            HStack(spacing: 8) {
                TextField("dominio.com", text: $newBlockedSite)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addBlockedSite)
                Button("Bloquear", action: addBlockedSite).disabled(normalizedHost.isEmpty)
            }
            ForEach(store.settings.blockedSites, id: \.self) { host in
                SettingsItem(symbolName: "nosign", tint: .red, title: host) {
                    Button("Quitar") {
                        store.settings.blockedSites.removeAll { $0 == host }
                        store.saveSoon()
                    }
                }
            }
        }
        SettingsGroup(title: "Excepciones del bloqueador de anuncios") {
            if store.settings.blockerDisabledHosts.isEmpty {
                Text("El bloqueador está activo en todos los sitios.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(store.settings.blockerDisabledHosts.sorted(), id: \.self) { host in
                SettingsItem(symbolName: "shield.slash", tint: .gray, title: host) {
                    Button("Reactivar") { store.setBlocker(enabled: true, host: host) }
                }
            }
        }
    }

    private func clearHistory() {
        store.profiles.forEach { store.history.clear(profileID: $0.id) }
        statusMessage = "Historial borrado"
    }

    private func clearConversations() {
        let alert = NSAlert()
        alert.messageText = "¿Borrar todas las conversaciones?"
        alert.informativeText = "No se puede deshacer."
        alert.addButton(withTitle: "Borrar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ConversationStore.shared.deleteAll()
        statusMessage = "Conversaciones borradas"
    }

    private func clearCaches() {
        let profileIDs = store.profiles.map(\.id)
        Task {
            await WebConfigurationFactory.deleteCaches(profileIDs: profileIDs)
            statusMessage = "Caché vaciada"
        }
    }

    private func clearAllWebsiteData() {
        let alert = NSAlert()
        alert.messageText = "¿Borrar cookies y sesiones de todos los perfiles?"
        alert.informativeText = "Vas a tener que volver a iniciar sesión en todos los sitios."
        alert.addButton(withTitle: "Borrar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let profileIDs = store.profiles.map(\.id)
        Task {
            for profileID in profileIDs { await WebConfigurationFactory.deleteData(profileID: profileID) }
            statusMessage = "Cookies y sesiones borradas"
        }
    }

    private var normalizedHost: String {
        let trimmed = newBlockedSite.trimmingCharacters(in: .whitespaces).lowercased()
        let host = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)?.host() ?? trimmed
        return host.replacingOccurrences(of: WebConstants.wwwPrefix, with: "")
    }

    private func addBlockedSite() {
        let host = normalizedHost
        guard !host.isEmpty, !store.settings.blockedSites.contains(host) else { return }
        store.settings.blockedSites.append(host)
        store.saveSoon()
        newBlockedSite = ""
    }
}

struct EnabledMark: View {
    var body: some View {
        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green).accessibilityLabel("Activado")
    }
}

struct PasswordSettings: View {
    @ViewState private var statusMessage = ""
    private var store: BrowserStore { BrowserStore.shared }

    var body: some View {
        SettingsGroup(title: "Llavero de macOS", footer: "Exporta desde la app Contraseñas (Archivo → Exportar) o desde Chrome. Borra el CSV después de importarlo.") {
            SettingsItem(symbolName: "key.fill", tint: .gray, title: "Rellenar contraseñas", detail: "Solo cuando lo pides, con Touch ID.") {
                Text("⌘\\").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
            SettingsItem(symbolName: "square.and.arrow.down", tint: .blue, title: "Importar desde CSV") {
                Button("Importar…", action: importPasswords)
            }
        }
        SettingsGroup(title: "Nunca guardar en") {
            if store.settings.passwordNeverHosts.isEmpty {
                Text("Ningún sitio.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(store.settings.passwordNeverHosts.sorted(), id: \.self) { host in
                SettingsItem(symbolName: "key.slash", tint: .gray, title: host) {
                    Button("Quitar") {
                        store.settings.passwordNeverHosts.remove(host)
                        store.saveSoon()
                    }
                }
            }
        }
        if !statusMessage.isEmpty { SettingsStatus(message: statusMessage) }
    }

    private func importPasswords() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        do {
            let importedCount = try PasswordVault.shared.importCSV(at: fileURL)
            statusMessage = "\(importedCount) contraseñas importadas al Llavero. Borra el archivo CSV."
        } catch {
            statusMessage = "No se pudieron importar: \(error.localizedDescription)"
        }
    }
}

struct DocumentSettings: View {
    private var store: BrowserStore { BrowserStore.shared }

    var body: some View {
        SettingsGroup(title: "Nuevo documento", footer: "Escribe docs en la command bar (⌘T) para crear un documento nuevo en el servicio elegido.") {
            ForEach(DocsProvider.allCases) { provider in
                Button {
                    store.settings.docsProvider = provider
                    store.saveSoon()
                } label: {
                    HStack(spacing: 12) {
                        FaviconView(url: provider.logoURL, size: 18)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white))
                        Text(provider.displayName).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: store.settings.docsProvider == provider ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.settings.docsProvider == provider ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        SettingsGroup(title: "Cuentas", footer: "La sesión se guarda en el perfil del Space activo.") {
            ForEach(DocsProvider.allCases) { provider in
                SettingsItem(symbolName: "person.badge.key", tint: .blue, title: provider.displayName) {
                    Button("Iniciar sesión") { AppDelegate.shared.openInMainWindow(provider.signInURL) }
                }
            }
        }
    }
}

struct AdvancedSettings: View {
    private static let suspendOptions = [1, 5, 10, 15, 60, 0]
    private static let revealDelayOptions = [0, 100, 200, 350, 500]

    private static func suspendLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Nunca"
        case 1: "1 minuto"
        default: "\(minutes) minutos"
        }
    }

    private var developerModeBinding: Binding<Bool> {
        Binding(
            get: { BrowserStore.shared.settings.developerMode },
            set: { isEnabled in
                BrowserStore.shared.settings.developerMode = isEnabled
                BrowserStore.shared.saveSoon()
                NSApp.mainMenu = MainMenu.build()
            }
        )
    }

    var body: some View {
        SettingsGroup {
            SettingsToggle(symbolName: "speaker.wave.2.fill", tint: .blue, title: "Sonidos de Parsec", isOn: SettingsBinding.make(\.playsSounds))
            SettingsItem(symbolName: "sidebar.squares.left", tint: .orange, title: "Retraso al abrir los paneles", detail: "Tiempo que el cursor debe quedarse en el borde para mostrar el sidebar o el panel de IA.") {
                ParsecSelect(selection: SettingsBinding.make(\.edgeRevealDelayMilliseconds), options: Self.revealDelayOptions.map { ($0, $0 == 0 ? "Inmediato" : "\($0) ms") }, width: 120)
            }
            SettingsToggle(symbolName: "link", tint: .gray, title: "Mostrar la URL completa", detail: "En la barra de dirección, en lugar del dominio.", isOn: SettingsBinding.make(\.showsFullURL))
        }
        SettingsGroup {
            SettingsToggle(symbolName: "macwindow.on.rectangle", tint: .green, title: "Links externos en ventana flotante", detail: "Si está apagado, se abren como pestaña en el Space activo.", isOn: SettingsBinding.make(\.opensExternalLinksInLittleWindow))
            SettingsItem(symbolName: "moon.zzz.fill", tint: .indigo, title: "Suspender pestañas inactivas", detail: "Cierra el proceso de la página para liberar memoria y CPU; se recarga al volver. No suspende las que reproducen audio o video.") {
                ParsecSelect(selection: SettingsBinding.make(\.suspendAfterMinutes), options: Self.suspendOptions.map { ($0, Self.suspendLabel($0)) }, width: 120)
            }
        }
        SettingsGroup(title: "Desarrollador", footer: "Se aplica a las pestañas que abras a partir de ahora.") {
            SettingsToggle(symbolName: "hammer.fill", tint: .gray, title: "Modo desarrollador", detail: "Inspeccionar elemento, menú Desarrollador y registro del agente.", isOn: developerModeBinding)
        }
    }
}
