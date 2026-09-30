import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum IntegrationTab: String, CaseIterable {
    case skills = "Skills"
    case mcps = "MCPs"
}

struct IntegrationSettings: View {
    @ViewState private var selection = IntegrationTab.mcps
    @ViewState private var editingServer: MCPServer?
    @ViewState private var importMessage = ""
    private var store: IntegrationStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ParsecSegmented(selection: $selection, options: IntegrationTab.allCases.map { ($0, $0.rawValue) })
                Spacer()
                Menu {
                    Button("Agregar MCP", systemImage: "plus", action: addServer)
                    Button("Importar MCPs desde JSON…", systemImage: "curlybraces", action: importMCPs)
                    Button("Importar skill o carpeta de plugin…", systemImage: "doc.badge.plus", action: importSkills)
                } label: {
                    Label("Agregar", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            Text(selection == .mcps ? "Conectá tus aplicaciones para que el asistente pueda consultar información y realizar acciones desde el navegador." : "Agregá instrucciones para personalizar cómo trabaja el asistente. Las skills activas se aplican al chat y a la navegación.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = store.errorMessage {
                IntegrationNotice(text: error, isError: true)
            }
            if !importMessage.isEmpty { IntegrationNotice(text: importMessage, isError: false) }
            if selection == .mcps { serversContent }
            else { skillsContent }
        }
        .sheet(item: $editingServer) { server in
            MCPServerEditor(server: server)
        }
    }

    @ViewBuilder
    private var serversContent: some View {
        if store.servers.isEmpty {
            IntegrationEmptyState(symbol: "puzzlepiece.extension", title: "Conectá tu primer MCP", detail: "Agregá la URL de un servidor remoto o el comando de uno instalado en tu Mac.", buttonTitle: "Agregar MCP", action: addServer)
        } else {
            SettingsGroup(title: "Servidores MCP · \(store.servers.count)") {
                ForEach(store.servers) { server in
                    MCPServerRow(server: server, edit: editServer)
                }
            }
        }
        SettingsGroup(title: "Cómo conectar", footer: "Las credenciales se guardan en el llavero de macOS. Los MCPs activados están disponibles con todos los proveedores de IA.") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Remoto: URL Streamable HTTP y token opcional.", systemImage: "network")
                Label("Local: comando, argumentos y variables de entorno.", systemImage: "terminal")
                Label("Importación: archivo JSON con mcpServers.", systemImage: "square.and.arrow.down")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var skillsContent: some View {
        if !store.skills.isEmpty {
            SettingsGroup(title: "Skills importadas · \(store.skills.count)", footer: "Se importan las instrucciones de SKILL.md. Esta versión no ejecuta scripts ni instala dependencias del plugin.") {
                ForEach(store.skills) { skill in InstalledSkillRow(skill: skill) }
            }
        } else {
            IntegrationEmptyState(symbol: "doc.text", title: "Tus skills, en Parsec", detail: "Importá un archivo Markdown o una carpeta con archivos SKILL.md para sumar instrucciones al asistente.", buttonTitle: "Importar skill", action: importSkills)
        }
        SettingsGroup(title: "Incluidas en Parsec · \(AgentCommand.all.count)") {
            ForEach(AgentCommand.all) { command in
                HStack(spacing: 12) {
                    IntegrationIcon(symbol: command.symbolName)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(command.title).font(.system(size: 13, weight: .medium))
                        Text(command.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Text("/\(command.keyword)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func addServer() { editingServer = MCPServer(name: "", transport: .http) }
    private func editServer(_ server: MCPServer) { editingServer = server }

    private func importMCPs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Importar MCPs"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try store.importMCPs(from: url)
            selection = .mcps
            store.errorMessage = nil
            importMessage = count == 1 ? "1 MCP importado. Usá Conectar para comprobarlo." : "\(count) MCPs importados. Usá Conectar para comprobarlos."
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func importSkills() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.prompt = "Importar skills"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try store.importSkills(from: url)
            selection = .skills
            store.errorMessage = nil
            importMessage = count == 1 ? "1 skill importada y activada." : "\(count) skills importadas y activadas."
        } catch { store.errorMessage = error.localizedDescription }
    }
}

private struct IntegrationIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17))
            .frame(width: 34, height: 34)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

private struct IntegrationNotice: View {
    let text: String
    let isError: Bool
    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
            .font(.system(size: 12))
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct IntegrationEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 330)
            Button(buttonTitle, action: action).buttonStyle(.borderedProminent).controlSize(.regular)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MCPServerRow: View {
    let server: MCPServer
    let edit: (MCPServer) -> Void
    @ViewState private var isToolsExpanded = false
    private var store: IntegrationStore { .shared }
    private var state: MCPConnectionState { store.states[server.id] ?? .disconnected }
    private var isConnecting: Bool { state == .connecting }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IntegrationIcon(symbol: server.transport == .http ? "network" : "terminal")
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name).font(.system(size: 13, weight: .medium))
                    Text(server.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text(server.isEnabled ? state.title : "Desactivado")
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isConnecting { ProgressView().controlSize(.small) }
                Toggle("Activar \(server.name)", isOn: Binding(get: getEnabled, set: setEnabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                Menu {
                    Button("Editar", systemImage: "pencil", action: editServer)
                    Button("Eliminar", systemImage: "trash", role: .destructive, action: removeServer)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Opciones de \(server.name)")
            }
            HStack {
                Button(connectionButtonTitle, action: connect).controlSize(.small).disabled(isConnecting || !server.isEnabled)
                if let tools = store.tools[server.id], !tools.isEmpty {
                    Button(isToolsExpanded ? "Ocultar herramientas" : "Ver herramientas", action: toggleTools).controlSize(.small)
                }
                Spacer()
            }
            .padding(.leading, 46)
            if isToolsExpanded, let tools = store.tools[server.id] {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tools) { tool in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.name).font(.system(size: 11, weight: .medium, design: .monospaced))
                            if !tool.description.isEmpty { Text(tool.description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
                        }
                    }
                }
                .padding(.leading, 46)
            }
        }
    }

    private var statusColor: Color {
        guard server.isEnabled else { return .secondary }
        switch state {
        case .connected: return .green
        case .failed: return .red
        case .connecting, .disconnected: return .secondary
        }
    }

    private var connectionButtonTitle: String {
        if case .connected = state { return "Volver a conectar" }
        return "Conectar"
    }
    private func getEnabled() -> Bool { server.isEnabled }
    private func setEnabled(_ enabled: Bool) { store.setEnabled(server.id, enabled: enabled) }
    private func editServer() { edit(server) }
    private func toggleTools() { isToolsExpanded.toggle() }
    private func connect() { Task { await store.testConnection(server.id) } }
    private func removeServer() {
        guard confirmIntegrationRemoval(server.name) else { return }
        do { try store.removeServer(server.id) }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private struct InstalledSkillRow: View {
    let skill: InstalledSkill
    @ViewState private var isExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IntegrationIcon(symbol: "doc.text")
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name).font(.system(size: 13, weight: .medium))
                    Text(skill.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Toggle("Activar \(skill.name)", isOn: Binding(get: getEnabled, set: setEnabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                Menu {
                    Button("Ver instrucciones", action: toggleInstructions)
                    Button("Eliminar", role: .destructive, action: remove)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Opciones de \(skill.name)")
            }
            if isExpanded {
                Text(skill.instructions).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func getEnabled() -> Bool { skill.isEnabled }
    private func setEnabled(_ enabled: Bool) { IntegrationStore.shared.setSkillEnabled(skill.id, enabled: enabled) }
    private func toggleInstructions() { isExpanded.toggle() }
    private func remove() {
        guard confirmIntegrationRemoval(skill.name) else { return }
        IntegrationStore.shared.removeSkill(skill.id)
    }
}

@MainActor
private func confirmIntegrationRemoval(_ name: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Eliminar \(name)"
    alert.informativeText = "Dejará de estar disponible para el asistente. Podés volver a agregarlo cuando quieras."
    alert.addButton(withTitle: "Eliminar")
    alert.addButton(withTitle: "Cancelar")
    return alert.runModal() == .alertFirstButtonReturn
}

struct MCPServerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState private var server: MCPServer
    @ViewState private var token = ""
    @ViewState private var argumentsText = "[]"
    @ViewState private var environmentText = "{}"
    @ViewState private var headers: [String: String] = [:]
    @ViewState private var errorMessage = ""
    @ViewState private var canSave = true

    init(server: MCPServer) { _server = ViewState(initialValue: server) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(server.name.isEmpty ? "Agregar MCP" : "Editar MCP").font(.system(size: 20, weight: .semibold))
            Form {
                TextField("Nombre", text: $server.name, prompt: Text("Nombre de la aplicación"))
                Picker("Conexión", selection: $server.transport) {
                    ForEach(MCPTransport.allCases) { transport in Text(transport.title).tag(transport) }
                }
                if server.transport == .http {
                    TextField("URL del MCP", text: $server.endpoint, prompt: Text("https://aplicacion.com/mcp"))
                    SecureField("Token de acceso", text: $token, prompt: Text("Opcional · guardado en el llavero"))
                    Text("Usá el endpoint Streamable HTTP de la aplicación. Para conexiones con OAuth, obtené un token en la aplicación y agregalo aquí.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    TextField("Comando", text: $server.command, prompt: Text("npx, uvx o ruta del ejecutable"))
                    LabeledContent("Argumentos (JSON)") { TextField("[\"-y\", \"paquete-mcp\"]", text: $argumentsText) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Variables de entorno (JSON)").font(.system(size: 12))
                        TextEditor(text: $environmentText).font(.system(size: 11, design: .monospaced)).frame(height: 90)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
                        Text("Ejemplo: {\"API_KEY\": \"tu-token\"}. Se guardan en el llavero.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Toggle("Disponible para el asistente", isOn: $server.isEnabled)
            }
            .formStyle(.grouped)
            if !errorMessage.isEmpty { IntegrationNotice(text: errorMessage, isError: true) }
            HStack {
                Spacer()
                Button("Cancelar", action: cancel).keyboardShortcut(.cancelAction)
                Button("Guardar", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 540, height: 480)
        .onAppear(perform: loadSecrets)
    }

    private func loadSecrets() {
        do {
            let secrets = try IntegrationSecretStore.read(server.id)
            token = secrets.token
            headers = secrets.headers
            argumentsText = String(decoding: try JSONEncoder().encode(server.arguments), as: UTF8.self)
            environmentText = String(decoding: try JSONEncoder().encode(secrets.environment), as: UTF8.self)
        } catch { errorMessage = error.localizedDescription; canSave = false }
    }

    private func cancel() { dismiss() }
    private func save() {
        do {
            server.name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
            server.endpoint = server.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            server.command = server.command.trimmingCharacters(in: .whitespacesAndNewlines)
            let environment: [String: String]
            if server.transport == .stdio {
                server.arguments = try JSONDecoder().decode([String].self, from: Data(argumentsText.utf8))
                environment = try JSONDecoder().decode([String: String].self, from: Data(environmentText.utf8))
            } else { environment = [:] }
            let secrets = MCPSecrets(token: token.trimmingCharacters(in: .whitespacesAndNewlines), environment: environment, headers: headers)
            try IntegrationStore.shared.save(server, secrets: secrets)
            IntegrationStore.shared.errorMessage = nil
            dismiss()
        } catch { errorMessage = error is DecodingError ? "Revisá el JSON: argumentos debe ser una lista de textos y variables un objeto de textos." : error.localizedDescription }
    }
}
