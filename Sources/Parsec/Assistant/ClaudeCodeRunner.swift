import Foundation

@MainActor
final class ClaudeCodeRunner: AssistantRun {
    private static let executableCandidates = [".local/bin/claude", ".claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    private static let installHint = "No encontré Claude Code. Instálalo desde claude.com/claude-code y ejecuta claude una vez en la Terminal para iniciar sesión."
    private static let readTool = "Read"
    private static let webTools = ["WebSearch", "WebFetch"]
    private static let mcpToolPrefix = "mcp__"

    private let process = Process()
    private let lineReader = JSONLineReader()
    private var errorOutput = Data()
    private var hasFinished = false
    private let onEvent: @MainActor (AssistantEvent) -> Void

    static var executableURL: URL? {
        CommandLineTool.locate(executableCandidates)
    }

    init(onEvent: @escaping @MainActor (AssistantEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start(_ request: AssistantRequest) {
        guard let executableURL = Self.executableURL else { return onEvent(.failed(Self.installHint)) }
        let enabledTools = (request.attachments.isEmpty ? [] : [Self.readTool]) + (request.usesWebSearch ? Self.webTools : [])
        let connectorTools = request.enabledConnectors.map { Self.mcpToolPrefix + ConnectorCatalog.toolName(for: $0) }
        var arguments = [
            "-p", request.prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--tools", enabledTools.joined(separator: ","),
            "--setting-sources", "project",
            "--append-system-prompt", request.systemPrompt,
        ]
        let allowedTools = enabledTools + connectorTools
        if !allowedTools.isEmpty { arguments += ["--allowedTools", allowedTools.joined(separator: ",")] }
        if request.enabledConnectors.isEmpty { arguments.append("--strict-mcp-config") }
        if let resumeSessionID = request.resumeSessionID { arguments += ["--resume", resumeSessionID] }
        if !request.model.isEmpty { arguments += ["--model", request.model] }
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = AssistantWorkspace.folderURL
        process.environment = CommandLineTool.environment(for: executableURL)
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.consume(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.errorOutput.append(data) }
        }
        process.terminationHandler = { [weak self] _ in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.finishIfNeeded() }
        }
        do {
            try process.run()
        } catch {
            onEvent(.failed("No se pudo iniciar Claude Code: \(error.localizedDescription)"))
        }
    }

    func cancel() {
        guard process.isRunning else { return }
        process.terminate()
    }

    private func consume(_ data: Data) {
        lineReader.append(data).forEach(handle)
    }

    private func handle(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        if type == "result" {
            hasFinished = true
            onEvent(.finished(text: payload["result"] as? String ?? "", sessionID: payload["session_id"] as? String, isError: payload["is_error"] as? Bool ?? false))
            return
        }
        guard type == "stream_event", let event = payload["event"] as? [String: Any] else { return }
        let contentBlock = event["content_block"] as? [String: Any]
        if event["type"] as? String == "content_block_start", contentBlock?["type"] as? String == "tool_use", let toolName = contentBlock?["name"] as? String {
            return onEvent(.toolStarted(toolName))
        }
        guard let delta = event["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String else { return }
        onEvent(.textDelta(text))
    }

    private func finishIfNeeded() {
        guard !hasFinished else { return }
        hasFinished = true
        let errorText = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        onEvent(.failed(errorText.isEmpty ? "Claude Code terminó sin responder." : errorText))
    }
}

final class JSONLineReader {
    private static let lineSeparator = UInt8(ascii: "\n")
    private var pending = Data()

    func append(_ data: Data) -> [[String: Any]] {
        pending.append(data)
        var payloads: [[String: Any]] = []
        while let newlineIndex = pending.firstIndex(of: Self.lineSeparator) {
            let line = pending.subdata(in: pending.startIndex..<newlineIndex)
            pending.removeSubrange(pending.startIndex...newlineIndex)
            if let payload = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { payloads.append(payload) }
        }
        return payloads
    }
}

@MainActor
@Observable
final class ConnectorCatalog {
    static let shared = ConnectorCatalog()
    nonisolated private static let listArguments = ["mcp", "list"]
    nonisolated private static let nameTerminator = ": "

    nonisolated static func toolName(for connector: String) -> String {
        String(connector.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    }

    private(set) var connectors: [String] = []
    private(set) var isLoading = false
    @ObservationIgnored private var hasLoaded = false

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading, let executableURL = ClaudeCodeRunner.executableURL else { return }
        isLoading = true
        Task {
            connectors = await Self.readConnectors(executableURL: executableURL)
            hasLoaded = true
            isLoading = false
        }
    }

    nonisolated private static func readConnectors(executableURL: URL) async -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = listArguments
        process.environment = CommandLineTool.environment(for: executableURL)
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: output, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.contains(" - "), let terminator = line.range(of: nameTerminator) else { return nil }
            let trimmedName = line[..<terminator.lowerBound].trimmingCharacters(in: .whitespaces)
            return trimmedName.isEmpty ? nil : trimmedName
        }
    }
}
