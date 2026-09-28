import AppKit

struct MenuShortcutItem: Identifiable {
    let title: String
    let action: Selector
    let key: String
    let modifiers: NSEvent.ModifierFlags
    var tag = 0

    var id: String { NSStringFromSelector(action) + (tag == 0 ? "" : "#\(tag)") }
}

enum ShortcutCode {
    private static let separator: Character = "|"
    private static let modifierNames: [(NSEvent.ModifierFlags, String, String)] = [
        (.control, "ctrl", "⌃"), (.option, "opt", "⌥"), (.shift, "shift", "⇧"), (.command, "cmd", "⌘"),
    ]
    private static let keySymbols: [String: String] = [
        String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑", String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓",
        String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←", String(UnicodeScalar(NSRightArrowFunctionKey)!): "→",
        "\u{1b}": "esc",
    ]

    static func encode(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        let names = modifierNames.filter { modifiers.contains($0.0) }.map(\.1)
        return names.joined(separator: "+") + String(separator) + key
    }

    static func decode(_ code: String) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let parts = code.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        let names = Set(parts[0].split(separator: "+").map(String.init))
        let modifiers = modifierNames.filter { names.contains($0.1) }.reduce(into: NSEvent.ModifierFlags()) { $0.insert($1.0) }
        return (String(parts[1]), modifiers)
    }

    static func display(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        let symbols = modifierNames.filter { modifiers.contains($0.0) }.map(\.2).joined()
        return symbols + (keySymbols[key] ?? key.uppercased())
    }
}

@MainActor
enum MainMenu {
    private typealias Item = MenuShortcutItem

    private static let escapeKey = "\u{1b}"
    private static let spaceShortcutCount = 9

    private static let fileItems = [
        Item(title: "Nueva pestaña", action: #selector(BrowserWindow.newTabAction(_:)), key: "t", modifiers: .command),
        Item(title: "Nueva ventana privada", action: #selector(AppDelegate.newPrivateWindowAction(_:)), key: "n", modifiers: [.command, .shift]),
        Item(title: "Abrir ubicación…", action: #selector(BrowserWindow.editURLAction(_:)), key: "l", modifiers: .command),
        Item(title: "Abrir como pestaña", action: #selector(BrowserWindow.promoteToTabAction(_:)), key: "o", modifiers: .command),
        Item(title: "Cerrar pestaña", action: #selector(BrowserWindow.closeTabAction(_:)), key: "w", modifiers: .command),
        Item(title: "Reabrir pestaña cerrada", action: #selector(BrowserWindow.reopenTabAction(_:)), key: "t", modifiers: [.command, .shift]),
        Item(title: "Cerrar ventana", action: #selector(NSWindow.performClose(_:)), key: "w", modifiers: [.command, .shift]),
    ]
    private static let editItems = [
        Item(title: "Copiar URL", action: #selector(BrowserWindow.copyURLAction(_:)), key: "c", modifiers: [.command, .shift]),
        Item(title: "Buscar en la página…", action: #selector(BrowserWindow.findAction(_:)), key: "f", modifiers: .command),
        Item(title: "Buscar siguiente", action: #selector(BrowserWindow.findNextAction(_:)), key: "g", modifiers: .command),
        Item(title: "Buscar anterior", action: #selector(BrowserWindow.findPreviousAction(_:)), key: "g", modifiers: [.command, .shift]),
        Item(title: "Rellenar contraseña", action: #selector(BrowserWindow.fillPasswordAction(_:)), key: "\\", modifiers: .command),
    ]
    private static let viewItems = [
        Item(title: "Mostrar u ocultar sidebar", action: #selector(BrowserWindow.toggleSidebarAction(_:)), key: "s", modifiers: .command),
        Item(title: "Cambiar a pestañas arriba / sidebar", action: #selector(BrowserWindow.toggleLayoutAction(_:)), key: "s", modifiers: [.command, .option]),
        Item(title: "Preguntar a la IA", action: #selector(BrowserWindow.toggleAssistantAction(_:)), key: "j", modifiers: .command),
        Item(title: "Historial de conversaciones", action: #selector(BrowserWindow.toggleHistoryAction(_:)), key: "y", modifiers: .command),
        Item(title: "Recargar", action: #selector(BrowserWindow.reloadAction(_:)), key: "r", modifiers: .command),
        Item(title: "Atrás", action: #selector(BrowserWindow.goBackAction(_:)), key: "[", modifiers: .command),
        Item(title: "Adelante", action: #selector(BrowserWindow.goForwardAction(_:)), key: "]", modifiers: .command),
        Item(title: "Acercar", action: #selector(BrowserWindow.zoomInAction(_:)), key: "+", modifiers: .command),
        Item(title: "Alejar", action: #selector(BrowserWindow.zoomOutAction(_:)), key: "-", modifiers: .command),
        Item(title: "Tamaño real", action: #selector(BrowserWindow.actualSizeAction(_:)), key: "0", modifiers: .command),
    ]
    private static let tabItems = [
        Item(title: "Fijar o desfijar", action: #selector(BrowserWindow.togglePinAction(_:)), key: "d", modifiers: .command),
        Item(title: "Dividir vista", action: #selector(BrowserWindow.splitViewAction(_:)), key: "=", modifiers: [.command, .control]),
        Item(title: "Cerrar panel dividido", action: #selector(BrowserWindow.closePaneAction(_:)), key: "w", modifiers: [.command, .control]),
        Item(title: "Pestaña siguiente", action: #selector(BrowserWindow.nextTabAction(_:)), key: String(UnicodeScalar(NSDownArrowFunctionKey)!), modifiers: [.command, .option]),
        Item(title: "Pestaña anterior", action: #selector(BrowserWindow.previousTabAction(_:)), key: String(UnicodeScalar(NSUpArrowFunctionKey)!), modifiers: [.command, .option]),
    ]
    private static let spaceItems = [
        Item(title: "Nuevo Space…", action: #selector(BrowserWindow.newSpaceAction(_:)), key: "n", modifiers: [.command, .option]),
        Item(title: "Editar tema…", action: #selector(BrowserWindow.editThemeAction(_:)), key: "t", modifiers: [.command, .option]),
        Item(title: "Space siguiente", action: #selector(BrowserWindow.nextSpaceAction(_:)), key: String(UnicodeScalar(NSRightArrowFunctionKey)!), modifiers: [.command, .option]),
        Item(title: "Space anterior", action: #selector(BrowserWindow.previousSpaceAction(_:)), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), modifiers: [.command, .option]),
    ]

    private static let developerItems = [
        Item(title: "Recargar sin caché", action: #selector(BrowserWindow.reloadFromOriginAction(_:)), key: "r", modifiers: [.command, .option]),
        Item(title: "Ver código fuente", action: #selector(BrowserWindow.viewSourceAction(_:)), key: "u", modifiers: [.command, .option]),
        Item(title: "Copiar user agent", action: #selector(BrowserWindow.copyUserAgentAction(_:)), key: "", modifiers: []),
    ]

    static let configurableSections: [(title: String, items: [MenuShortcutItem])] = [
        ("Pestañas y ventanas", fileItems + tabItems),
        ("Navegación", viewItems),
        ("Edición", editItems),
        ("Spaces", spaceItems),
    ]

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu(appMenu()))
        mainMenu.addItem(submenu(fileMenu()))
        mainMenu.addItem(submenu(editMenu()))
        mainMenu.addItem(submenu(viewMenu()))
        mainMenu.addItem(submenu(tabsMenu()))
        mainMenu.addItem(submenu(spacesMenu()))
        if BrowserStore.shared.settings.developerMode {
            mainMenu.addItem(submenu(menu("Desarrollador", items: developerItems)))
        }
        let windowMenu = standardWindowMenu()
        mainMenu.addItem(submenu(windowMenu))
        NSApp.windowsMenu = windowMenu
        return mainMenu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Parsec")
        menu.addItem(withTitle: "Acerca de Parsec", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(makeItem(Item(title: "Configuración…", action: #selector(AppDelegate.openSettingsAction(_:)), key: ",", modifiers: .command)))
        menu.addItem(makeItem(Item(title: "Usar como navegador predeterminado", action: #selector(AppDelegate.setDefaultBrowserAction(_:)), key: "", modifiers: [])))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ocultar Parsec", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Ocultar otros", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de Parsec", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        menu("Archivo", items: fileItems)
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edición")
        menu.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        editItems.forEach { menu.addItem(makeItem($0)) }
        return menu
    }

    private static func viewMenu() -> NSMenu {
        menu("Visualización", items: viewItems + [
            Item(title: "Acercar", action: #selector(BrowserWindow.zoomInAction(_:)), key: "=", modifiers: .command),
            Item(title: "Cerrar panel flotante", action: #selector(BrowserWindow.dismissOverlayAction(_:)), key: escapeKey, modifiers: []),
        ])
    }

    private static func tabsMenu() -> NSMenu {
        menu("Pestañas", items: tabItems)
    }

    private static func spacesMenu() -> NSMenu {
        let numberedItems = (1...spaceShortcutCount).map { number in
            Item(title: "Space \(number)", action: #selector(BrowserWindow.selectSpaceAction(_:)), key: String(number), modifiers: .control, tag: number - 1)
        }
        return menu("Spaces", items: spaceItems + numberedItems)
    }

    private static func standardWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Ventana")
        menu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(makeItem(Item(title: "Ventana principal", action: #selector(AppDelegate.showMainWindowAction(_:)), key: "1", modifiers: [.command, .shift])))
        return menu
    }

    private static func menu(_ title: String, items: [Item]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach { menu.addItem(makeItem($0)) }
        return menu
    }

    static func shortcut(for item: MenuShortcutItem) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        BrowserStore.shared.settings.shortcutOverrides[item.id].flatMap(ShortcutCode.decode) ?? (item.key, item.modifiers)
    }

    private static func makeItem(_ item: Item) -> NSMenuItem {
        let shortcut = shortcut(for: item)
        let menuItem = NSMenuItem(title: item.title, action: item.action, keyEquivalent: shortcut.key)
        menuItem.keyEquivalentModifierMask = shortcut.modifiers
        menuItem.tag = item.tag
        return menuItem
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
