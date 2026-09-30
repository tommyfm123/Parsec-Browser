import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate { NSApp.delegate as! AppDelegate }

    private(set) var mainWindow: BrowserWindow?
    private var privateWindows: [BrowserWindow] = []
    private var littleWindows: [LittleWindow] = []
    private var settingsWindow: NSWindow?
    private var pendingURLs: [URL] = []
    private var hasFinishedLaunching = false

    var mainModel: WindowModel? { mainWindow?.model }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = BrowserStore.shared
        store.load()
        ContentBlocker.shared.prepare()
        store.visibleNodeIDs = { [weak self] in self?.visibleNodeIDs() ?? [] }
        store.startLifecycle()
        NSApp.mainMenu = MainMenu.build()
        #if DEBUG
        DebugBridge.start()
        #endif
        showMainWindow()
        hasFinishedLaunching = true
        pendingURLs.forEach(openExternalURL)
        pendingURLs.removeAll()
        NSApp.activate()
    }

    func applicationDidResignActive(_ notification: Notification) {
        mainModel?.setPictureInPictureForVisibleTabs(isEntering: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        mainModel?.setPictureInPictureForVisibleTabs(isEntering: false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard BrowserStore.shared.settings.confirmsBeforeQuit else { return .terminateNow }
        return QuitConfirmation.isConfirmed() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrowserStore.shared.saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard hasFinishedLaunching else { return pendingURLs.append(contentsOf: urls) }
        urls.forEach(openExternalURL)
    }

    func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = BrowserWindow(model: WindowModel())
        window.onClose = { [weak self] in self?.mainWindow = nil }
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        if let selectedNode = window.model.selectedNode { window.model.select(selectedNode) }
    }

    func replayWelcome() {
        showMainWindow()
        mainModel?.isWelcomePresented = true
    }

    func openPrivateWindow() {
        let window = BrowserWindow(model: WindowModel(isPrivate: true))
        window.onClose = { [weak self, weak window] in self?.privateWindows.removeAll { $0 === window } }
        privateWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        window.model.presentCommandBar(mode: .newTab)
    }

    func openExternalURL(_ url: URL) {
        guard BrowserStore.shared.settings.opensExternalLinksInLittleWindow else {
            showMainWindow()
            _ = mainModel?.openInNewTab(url)
            NSApp.activate()
            return
        }
        openLittleWindow(for: url)
    }

    func openInMainWindow(_ url: URL) {
        showMainWindow()
        _ = mainModel?.openInNewTab(url)
    }

    func openLittleWindow(for url: URL) {
        let profileID = BrowserStore.shared.space(id: BrowserStore.shared.lastSpaceID)?.profileID ?? BrowserStore.shared.profiles[0].id
        let window = LittleWindow(model: LittleWindowModel(url: url, profileID: profileID))
        window.onClose = { [weak self, weak window] in self?.littleWindows.removeAll { $0 === window } }
        littleWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func adoptIntoMainWindow(_ node: SidebarNode) {
        showMainWindow()
        mainModel?.adopt(node)
    }

    func openSettings(section: SettingsSection = .general) {
        let hostingView = NSHostingView(rootView: SettingsView(initialSection: section))
        hostingView.sizingOptions = []
        let window = settingsWindow ?? makeSettingsWindow()
        window.contentView = hostingView
        window.setContentSize(SettingsView.size)
        if settingsWindow == nil { window.center() }
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Configuración de Parsec"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        return window
    }

    func setAsDefaultBrowser() {
        let appURL = Bundle.main.bundleURL
        for scheme in [WebConstants.httpScheme, WebConstants.httpsScheme] {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { _ in }
        }
    }

    @objc func openSettingsAction(_ sender: Any?) { openSettings() }
    @objc func setDefaultBrowserAction(_ sender: Any?) { setAsDefaultBrowser() }
    @objc func newPrivateWindowAction(_ sender: Any?) { openPrivateWindow() }
    @objc func showMainWindowAction(_ sender: Any?) { showMainWindow() }

    @objc func newTabAction(_ sender: Any?) {
        showMainWindow()
        mainModel?.presentCommandBar(mode: .newTab)
    }

    private func visibleNodeIDs() -> Set<UUID> {
        let windowModels = ([mainWindow] + privateWindows).compactMap { $0?.model }
        let browserIDs = windowModels.reduce(into: Set<UUID>()) { $0.formUnion($1.visibleNodeIDs) }
        return browserIDs.union(littleWindows.map(\.model.node.id))
    }
}

@MainActor
enum QuitConfirmation {
    static func isConfirmed() -> Bool {
        let alert = NSAlert()
        alert.messageText = "¿Seguro que quieres salir de Parsec?"
        alert.informativeText = "Se cerrarán todas las ventanas de Parsec."
        alert.addButton(withTitle: "Salir")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
enum CommandRouter {
    static func perform(_ action: CommandAction, in model: WindowModel) {
        switch action {
        case .newSpace: model.isNewSpacePresented = !model.isPrivate
        case .splitView: model.splitView()
        case .copyURL: model.copyCurrentURL()
        case .togglePin: model.togglePin()
        case .privateWindow: AppDelegate.shared.openPrivateWindow()
        case .editTheme: model.isThemeEditorPresented = !model.isPrivate
        case .toggleSidebar: model.toggleSidebarPinned()
        case .toggleLayout: toggleLayout()
        case .settings: AppDelegate.shared.openSettings()
        case .downloads: openDownloadsFolder()
        case .assistant: model.isAssistantPresented = true
        case .history: model.isHistoryPresented = !model.isPrivate
        }
    }

    static func toggleLayout() {
        let store = BrowserStore.shared
        store.settings.layout = store.settings.layout == .sidebar ? .topTabs : .sidebar
        store.saveSoon()
    }

    private static func openDownloadsFolder() {
        NSWorkspace.shared.open(DownloadManager.downloadFolderURL)
    }
}
