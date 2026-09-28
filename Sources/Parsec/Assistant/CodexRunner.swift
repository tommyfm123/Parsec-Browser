import Foundation

@MainActor
final class CodexRunner: AssistantRun {
    private static let executableCandidates = [".local/bin/codex", ".npm-global/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"]
    private static let installHint = "No encontré Codex CLI. Instálalo desde github.com/openai/codex y ejecuta codex una vez para iniciar sesión con ChatGPT."
    private static let imageFlag = "--image"

    private let process = Process()
    private var output = Data()
    private var errorOutput = Data()
    private let onEvent: @MainActor (AssistantEvent) -> Void

    static var executableURL: URL? {
        CommandLineTool.locate(executableCandidates)
    }

    init(onEvent: @escaping @MainActor (AssistantEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start(_ request: AssistantRequest) {
        guard let executableURL = Self.executableURL else { return onEvent(.failed(Self.installHint)) }
        let imageArguments = request.attachments.filter { $0.kind == .image }.flatMap { [Self.imageFlag, $0.fileURL.path] }
        let fileNotes = request.attachments.filter { $0.kind != .image }.map { "Archivo adjunto: \($0.fileURL.path)" }
        let prompt = ([request.systemPrompt] + fileNotes + [request.prompt]).joined(separator: "\n\n")
        var arguments = ["exec", "--skip-git-repo-check", "--sandbox", "read-only"] + imageArguments
        if !request.model.isEmpty { arguments += ["--model", request.model] }
        arguments.append(prompt)
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
            Task { @MainActor in self?.output.append(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.errorOutput.append(data) }
        }
        process.terminationHandler = { [weak self] finishedProcess in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            let status = finishedProcess.terminationStatus
            Task { @MainActor in self?.finish(status: status) }
        }
        do {
            try process.run()
        } catch {
            onEvent(.failed("No se pudo iniciar Codex: \(error.localizedDescription)"))
        }
    }

    func cancel() {
        guard process.isRunning else { return }
        process.terminate()
    }

    private func finish(status: Int32) {
        let text = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard status == 0, !text.isEmpty else { return onEvent(.failed(errorText.isEmpty ? "Codex terminó sin responder." : errorText)) }
        onEvent(.finished(text: text, sessionID: nil, isError: false))
    }
}
