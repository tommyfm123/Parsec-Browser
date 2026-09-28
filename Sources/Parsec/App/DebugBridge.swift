#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum DebugBridge {
    private static let notificationName = Notification.Name("dev.tommy.parsec.debug")
    nonisolated private static let actionKey = "action"
    nonisolated private static let argumentKey = "argument"
    private static let outputFolder = FileManager.default.temporaryDirectory.appending(path: "parsec-debug", directoryHint: .isDirectory)

    static func start() {
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        DistributedNotificationCenter.default().addObserver(forName: notificationName, object: nil, queue: .main) { notification in
            let action = notification.userInfo?[actionKey] as? String ?? ""
            let argument = notification.userInfo?[argumentKey] as? String ?? ""
            MainActor.assumeIsolated { perform(action, argument: argument) }
        }
    }

    private static func perform(_ action: String, argument: String) {
        guard let model = AppDelegate.shared.mainModel else { return }
        switch action {
        case "snapshot": snapshotWindows(named: argument)
        case "hoverSidebar": model.isSidebarHovering = argument != "off"
        case "pinSidebar": model.toggleSidebarPinned()
        case "commandBar": model.presentCommandBar(mode: .newTab); model.commandBar?.query = argument
        case "dismiss": _ = model.dismissTransientUI()
        case "open": InputResolver.destination(for: argument).map { _ = model.openInNewTab($0) }
        case "blank": _ = model.openInNewTab(nil)
        case "browse": model.isAssistantPresented = true; model.assistant.browse(argument)
        case "renderStart": render(StartPageView(model: model, cornerRadius: Radius.card).frame(width: 1100, height: 760), named: "start-render")
        case "renderModels": render(ModelPickerPopover {}.background(Color(nsColor: .windowBackgroundColor)), named: "models-render")
        case "renderDropdown": render(VStack(spacing: 20) { DropdownList(entries: { SpaceMenu.entries(model: model, space: model.currentSpace) }, width: 250) {}; ParsecSelect(selection: .constant(30), options: [(30, "30 minutos")]); ParsecSegmented(selection: .constant(SidebarLayout.sidebar), options: [(SidebarLayout.sidebar, "Sidebar"), (SidebarLayout.topTabs, "Arriba")]) }.padding().background(Color(nsColor: .windowBackgroundColor)), named: "dropdown-render")
        case "hit": probeHit(argument, in: model)
        case "space": model.switchToSpace(at: Int(argument) ?? 0)
        case "split": model.splitView()
        case "peek": InputResolver.destination(for: argument).map { url in model.activePage.map { model.openPeek(from: $0, url: url) } }
        case "layout": CommandRouter.toggleLayout()
        case "theme": model.isThemeEditorPresented.toggle()
        case "newSpace": model.isNewSpacePresented.toggle()
        case "little": InputResolver.destination(for: argument).map(AppDelegate.shared.openLittleWindow)
        case "private": AppDelegate.shared.openPrivateWindow()
        case "find": model.isFindBarVisible = true
        case "selectPinned": model.currentSpace.pinned.allTabs.first.map(model.select)
        case "assistant": model.isAssistantPresented.toggle()
        case "welcome": model.isWelcomePresented = true
        case "renderTheme": render(ArcThemeEditor(space: model.currentSpace), named: "theme-render")
        case "renderNewSpace": render(NewSpaceView(model: model), named: "newspace-render")
        case "settings": AppDelegate.shared.openSettings(section: SettingsSection(rawValue: argument) ?? .general)
        case "renderTopBar": render(TopTabsBar(model: model).frame(width: 1400), named: "topbar-render")
        case "renderAssistant": render(AssistantPanelView(model: model, assistant: model.assistant).frame(height: 760), named: "assistant-render")
        case "renderFolders": render(FolderPreviewList(model: model, space: BrowserStore.shared.spaces[Int(argument) ?? 0]), named: "folders-render")
        case "lifecycle": BrowserStore.shared.runLifecycleTick()
        default: break
        }
    }

    private static func probeHit(_ argument: String, in model: WindowModel) {
        let values = argument.split(separator: ",").compactMap { Double($0) }
        guard values.count == 2, let window = model.window, let contentView = window.contentView else { return }
        let point = NSPoint(x: values[0], y: window.frame.height - values[1])
        var view = contentView.hitTest(point)
        var chain: [String] = []
        while let current = view {
            chain.append("\(type(of: current)) \(current.frame)")
            view = current.superview
        }
        print("[HIT] " + chain.joined(separator: " <- "))
    }

    private struct FolderPreviewList: View {
        let model: WindowModel
        let space: Space

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(space.pinned.filter(\.isFolder)) { folder in
                    FolderRow(model: model, node: folder, depth: 0)
                }
            }
            .frame(width: 260)
            .padding(10)
            .background(Color(white: 0.9))
        }
    }

    private static func render(_ view: some View, named name: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let data = image.pngData else { return }
        try? data.write(to: outputFolder.appending(path: name + ".png"))
    }

    private static func snapshotWindows(named name: String) {
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let contentView = window.contentView, let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { continue }
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            let fileURL = outputFolder.appending(path: "\(name)-window\(index).png")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: fileURL)
        }
        guard let webView = AppDelegate.shared.mainModel?.activePage?.webView else { return }
        webView.takeSnapshot(with: nil) { image, _ in
            guard let data = image?.pngData else { return }
            try? data.write(to: outputFolder.appending(path: "\(name)-web.png"))
        }
    }
}
#endif
