import Foundation
import WebKit

@MainActor
enum DeveloperTools {
    private static let sourceScript = "return document.documentElement.outerHTML;"
    private static let userAgentScript = "return navigator.userAgent;"
    private static let sourceFileExtension = "txt"

    static func showSource(in model: WindowModel) {
        guard let page = model.activePage else { return }
        Task {
            guard let source = try? await page.webView.callAsyncJavaScript(sourceScript, arguments: [:], in: nil, contentWorld: .defaultClient) as? String else { return }
            let fileName = (page.currentHost.isEmpty ? UUID().uuidString : page.currentHost) + "." + sourceFileExtension
            let fileURL = FileManager.default.temporaryDirectory.appending(path: fileName)
            guard (try? source.write(to: fileURL, atomically: true, encoding: .utf8)) != nil else { return }
            _ = model.openInNewTab(fileURL)
        }
    }

    static func copyUserAgent(in model: WindowModel) {
        guard let webView = model.activePage?.webView else { return }
        Task {
            guard let userAgent = try? await webView.callAsyncJavaScript(userAgentScript, arguments: [:], in: nil, contentWorld: .defaultClient) as? String else { return }
            Clipboard.copy(userAgent)
        }
    }
}
