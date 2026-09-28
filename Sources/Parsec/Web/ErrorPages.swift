import AppKit

enum ErrorPages {
    private static let style = """
        <style>
        :root { color-scheme: light dark; }
        body { font: 15px -apple-system, system-ui; display: grid; place-items: center; min-height: 90vh; margin: 0; }
        main { max-width: 480px; padding: 32px; }
        h1 { font-size: 22px; margin: 0 0 8px; }
        p { line-height: 1.55; opacity: .8; }
        a { display: inline-block; margin-top: 12px; padding: 8px 14px; border-radius: 8px; background: #0a84ff; color: white; text-decoration: none; }
        a.secondary { background: transparent; color: inherit; border: 1px solid rgba(127,127,127,.4); }
        </style>
        """

    static func insecureConnection(for secureURL: URL) -> String {
        var components = URLComponents(url: secureURL, resolvingAgainstBaseURL: false)
        components?.scheme = WebConstants.httpScheme
        let insecureURL = components?.url?.absoluteString ?? secureURL.absoluteString
        let host = escape(secureURL.host() ?? "")
        return """
            <!doctype html><html><head><meta charset="utf-8">\(style)</head><body><main>
            <h1>Este sitio no tiene conexión segura</h1>
            <p><strong>\(host)</strong> no respondió por HTTPS. Si continúas, lo que envíes viajará sin cifrar.</p>
            <a class="secondary" href="\(WebConstants.httpContinueScheme):\(escape(insecureURL))">Continuar con HTTP</a>
            </main></body></html>
            """
    }

    static func blockedSite(host: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">\(style)</head><body><main>
        <h1>Sitio bloqueado</h1>
        <p><strong>\(escape(host))</strong> está en tu lista de sitios bloqueados. Puedes cambiarlo en Configuración → Privacidad.</p>
        </main></body></html>
        """
    }

    static func loadFailure(for url: URL, message: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">\(style)</head><body><main>
        <h1>No se pudo abrir la página</h1>
        <p>\(escape(message))</p>
        <a href="\(escape(url.absoluteString))">Reintentar</a>
        </main></body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

@MainActor
enum JavaScriptDialog {
    private static let acceptTitle = "Aceptar"
    private static let cancelTitle = "Cancelar"
    private static let promptFieldWidth: CGFloat = 280
    private static let promptFieldHeight: CGFloat = 24

    static func alert(message: String, host: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = host
        alert.informativeText = message
        alert.addButton(withTitle: acceptTitle)
        return alert
    }

    static func confirm(message: String, host: String) -> NSAlert {
        let alert = self.alert(message: message, host: host)
        alert.addButton(withTitle: cancelTitle)
        return alert
    }

    static func prompt(message: String, defaultText: String?, host: String) -> (NSAlert, NSTextField) {
        let alert = confirm(message: message, host: host)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: promptFieldWidth, height: promptFieldHeight))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        return (alert, field)
    }

    static func present(_ alert: NSAlert, in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let window else { return completion(alert.runModal()) }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }
}
