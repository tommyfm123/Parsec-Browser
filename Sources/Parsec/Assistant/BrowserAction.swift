import Foundation
import WebKit

struct BrowserAction: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case open
        case search
        case back
        case forward
        case reload
        case scroll
        case click
        case fill
        case switchSpace
        case split
        case closeTab
        case groupTabs
    }

    var id: String { [type.rawValue, url, query, text, selector, value, name, direction].compactMap { $0 }.joined(separator: "|") }

    let type: Kind
    var url: String?
    var newTab: Bool?
    var query: String?
    var direction: String?
    var text: String?
    var selector: String?
    var value: String?
    var name: String?
    var titles: [String]?

    var summary: String {
        switch type {
        case .open: "Abrir \(url ?? "")\(newTab == true ? " en una pestaña nueva" : "")"
        case .search: "Buscar “\(query ?? "")”"
        case .back: "Ir atrás"
        case .forward: "Ir adelante"
        case .reload: "Recargar la página"
        case .scroll: direction == "up" ? "Desplazar hacia arriba" : "Desplazar hacia abajo"
        case .click: "Hacer clic en “\(text ?? selector ?? "")”"
        case .fill: "Escribir “\(value ?? "")” en \(selector ?? "un campo")"
        case .switchSpace: "Cambiar al Space \(name ?? "")"
        case .split: "Abrir \(url ?? "") en vista dividida"
        case .closeTab: "Cerrar “\(text ?? "")”"
        case .groupTabs: "Agrupar \(titles?.count ?? 0) pestañas en la carpeta “\(name ?? "")”"
        }
    }

    var symbolName: String {
        switch type {
        case .open, .split: "safari"
        case .search: "magnifyingglass"
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .reload: "arrow.clockwise"
        case .scroll: "arrow.up.and.down"
        case .click: "cursorarrow.click"
        case .fill: "character.cursor.ibeam"
        case .switchSpace: "square.stack"
        case .closeTab: "xmark.square"
        case .groupTabs: "folder.badge.plus"
        }
    }
}

enum AssistantResponseParser {
    private static let actionsOpenTag = "<parsec-actions>"
    private static let actionsCloseTag = "</parsec-actions>"

    static func visibleText(_ text: String) -> String {
        guard let openRange = text.range(of: actionsOpenTag) else { return text }
        return String(text[..<openRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func actions(in text: String) -> [BrowserAction] {
        guard let openRange = text.range(of: actionsOpenTag),
              let closeRange = text.range(of: actionsCloseTag, range: openRange.upperBound..<text.endIndex) else { return [] }
        let payload = Data(text[openRange.upperBound..<closeRange.lowerBound].utf8)
        return (try? JSONDecoder().decode([BrowserAction].self, from: payload)) ?? []
    }
}

@MainActor
enum BrowserActionExecutor {
    private static let scrollScript = "window.scrollBy({ top: direction * window.innerHeight * 0.8, behavior: 'smooth' }); return true;"
    private static let clickScript = """
        const clickable = 'a, button, [role=button], input[type=submit], input[type=button], summary, label';
        let element = selector ? document.querySelector(selector) : null;
        if (!element && text) {
          const wanted = text.trim().toLowerCase();
          element = Array.from(document.querySelectorAll(clickable)).find((candidate) =>
            (candidate.innerText || candidate.value || candidate.getAttribute('aria-label') || '').trim().toLowerCase().includes(wanted));
        }
        if (!element) return false;
        element.scrollIntoView({ block: 'center' });
        element.click();
        return true;
        """
    private static let fillScript = """
        const field = document.querySelector(selector);
        if (!field) return false;
        const prototype = field instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(prototype, 'value').set.call(field, value);
        field.dispatchEvent(new Event('input', { bubbles: true }));
        field.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
        """

    static func run(_ actions: [BrowserAction], in model: WindowModel) async -> [String] {
        var failures: [String] = []
        for action in actions {
            let didSucceed = await perform(action, in: model)
            if !didSucceed { failures.append(action.summary) }
        }
        return failures
    }

    private static func perform(_ action: BrowserAction, in model: WindowModel) async -> Bool {
        switch action.type {
        case .open:
            guard let url = destination(action.url) else { return false }
            action.newTab == true ? _ = model.openInNewTab(url) : model.open(url, mode: .navigateCurrent)
            return true
        case .search:
            guard let url = searchURL(action.query) else { return false }
            _ = model.openInNewTab(url)
            return true
        case .back:
            model.goBack()
            return true
        case .forward:
            model.goForward()
            return true
        case .reload:
            model.reload()
            return true
        case .scroll:
            return await evaluate(scrollScript, arguments: ["direction": action.direction == "up" ? -1 : 1], in: model)
        case .click:
            return await evaluate(clickScript, arguments: ["selector": action.selector ?? "", "text": action.text ?? ""], in: model)
        case .fill:
            guard let selector = action.selector else { return false }
            return await evaluate(fillScript, arguments: ["selector": selector, "value": action.value ?? ""], in: model)
        case .switchSpace:
            guard let space = model.spaces.first(where: { $0.title.localizedCaseInsensitiveCompare(action.name ?? "") == .orderedSame }) else { return false }
            model.switchToSpace(space)
            return true
        case .split:
            guard let url = destination(action.url) else { return false }
            let node = model.openInNewTab(url, inBackground: true)
            model.addToSplit(node.id)
            return true
        case .closeTab:
            guard let node = tabNode(matching: action.text, in: model) else { return false }
            model.close(node)
            return true
        case .groupTabs:
            return group(titles: action.titles ?? [], folderName: action.name ?? "Carpeta", in: model)
        }
    }

    private static func tabNode(matching title: String?, in model: WindowModel) -> SidebarNode? {
        guard let title, !title.isEmpty else { return nil }
        let candidates = (model.currentSpace.today + model.currentSpace.pinned).allTabs
        return candidates.first { $0.displayTitle.localizedCaseInsensitiveCompare(title) == .orderedSame }
            ?? candidates.first { $0.displayTitle.localizedCaseInsensitiveContains(title) }
    }

    private static func group(titles: [String], folderName: String, in model: WindowModel) -> Bool {
        let nodes = titles.compactMap { tabNode(matching: $0, in: model) }
        guard !nodes.isEmpty, !model.isPrivate else { return false }
        let store = BrowserStore.shared
        let folder = SidebarNode.folder(title: folderName)
        store.insert(folder, into: .pinned(spaceID: model.currentSpace.id), at: 0)
        nodes.forEach { store.move($0.id, into: .folder(nodeID: folder.id)) }
        return true
    }

    private static func destination(_ text: String?) -> URL? {
        text.flatMap(InputResolver.destination(for:))
    }

    private static func searchURL(_ text: String?) -> URL? {
        text.flatMap(InputResolver.searchURL(for:))
    }

    private static func evaluate(_ script: String, arguments: [String: Any], in model: WindowModel) async -> Bool {
        guard let webView = model.activePage?.webView else { return false }
        let result = try? await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .defaultClient)
        return result as? Bool ?? false
    }
}
