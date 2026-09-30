import AppKit
import Carbon
import SwiftUI

private let miniPopupHotKeyHandler: EventHandlerProcPtr = { _, _, userData in
    guard let userData else { return noErr }
    let controller = Unmanaged<MiniPopupController>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in controller.toggle() }
    return noErr
}

struct MiniPopupHotKey: Codable, Equatable {
    static let standard = MiniPopupHotKey(keyCode: UInt32(kVK_ANSI_P), key: "p", modifierFlags: NSEvent.ModifierFlags([.command, .option]).rawValue)
    private static let carbonModifierMap: [(NSEvent.ModifierFlags, Int)] = [
        (.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey),
    ]

    var keyCode: UInt32
    var key: String
    var modifierFlags: UInt

    init(keyCode: UInt32, key: String, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.key = key
        self.modifierFlags = modifierFlags
    }

    init(_ shortcut: RecordedShortcut) {
        self.init(keyCode: UInt32(shortcut.keyCode), key: shortcut.key, modifierFlags: shortcut.modifiers.rawValue)
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    var displayText: String { ShortcutCode.display(key: key, modifiers: modifiers) }

    var carbonModifiers: UInt32 {
        Self.carbonModifierMap.filter { modifiers.contains($0.0) }.reduce(0) { $0 | UInt32($1.1) }
    }
}

enum MiniPopupMetrics {
    static let cardWidth: CGFloat = 640
    static let cardRadius: CGFloat = 26
    static let shadowInset: CGFloat = 40
    static let bottomMargin: CGFloat = 24
    static let conversationHeight: CGFloat = 320
    static let estimatedCardHeight: CGFloat = 104
}

@MainActor
final class MiniPopupController {
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x50525343), id: 1)
    private static let conversationInactivityLimit: TimeInterval = 15 * 60

    static let didShowNotification = Notification.Name("ParsecMiniPopupDidShow")
    static let shared = MiniPopupController()

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var panel: MiniPopupPanel?
    private var hostingView: NSHostingView<MiniPopupView>?
    private var model: WindowModel?
    private var assistant: AssistantModel?
    private var lastInteractionAt: Date?
    private var cardHeight = MiniPopupMetrics.estimatedCardHeight
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func configure(isEnabled: Bool) {
        if isEnabled {
            _ = registerHotKey()
        } else {
            unregisterHotKey()
        }
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) -> Bool {
        guard isEnabled else {
            unregisterHotKey()
            dismiss()
            return true
        }
        return registerHotKey()
    }

    func setHotKey(_ shortcut: MiniPopupHotKey) -> Bool {
        guard hotKey != nil else { return true }
        let previous = BrowserStore.shared.settings.miniPopupHotKey
        unregisterHotKey()
        guard registerHotKey(shortcut) else {
            _ = registerHotKey(previous)
            return false
        }
        return true
    }

    func toggle() {
        guard let panel else { return show() }
        if panel.isVisible {
            dismiss()
            return
        }
        show()
    }

    func dismiss() {
        panel?.orderOut(nil)
        removeOutsideClickMonitors()
    }

    func show() {
        if panel == nil {
            _ = makePanel()
        } else {
            startFreshConversationIfExpired()
        }
        guard let panel else { return }
        lastInteractionAt = Date()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitors()
        NotificationCenter.default.post(name: Self.didShowNotification, object: nil)
    }

    private func updateCardHeight(_ height: CGFloat) {
        lastInteractionAt = Date()
        guard let panel, abs(height - cardHeight) > 0.5 else { return }
        cardHeight = height
        position(panel)
    }

    private func startFreshConversationIfExpired() {
        guard let lastInteractionAt,
              Date().timeIntervalSince(lastInteractionAt) >= Self.conversationInactivityLimit,
              let assistant,
              !assistant.isRunning else { return }
        startFreshConversation()
    }

    private func startFreshConversation() {
        assistant?.stop()
        replaceAssistant()
    }

    private func continueInBrowser() {
        guard let model, let assistant, let window = model.window else { return }
        model.addAgent(assistant)
        model.isAssistantPresented = true
        dismiss()
        replaceAssistant()
        window.makeKeyAndOrderFront(nil)
    }

    private func replaceAssistant() {
        guard let model else { return }
        let assistant = makeAssistant(for: model)
        self.assistant = assistant
        hostingView?.rootView = miniPopupView(model: model, assistant: assistant)
        lastInteractionAt = Date()
    }

    private func makeAssistant(for model: WindowModel) -> AssistantModel {
        let assistant = AssistantModel(windowModel: model)
        assistant.contextScope = .none
        return assistant
    }

    private func installOutsideClickMonitors() {
        guard localClickMonitor == nil, globalClickMonitor == nil else { return }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.dismissIfOutside(point) }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.dismissIfOutside(point) }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func dismissIfOutside(_ point: NSPoint) {
        guard let panel, panel.isVisible else { return }
        let cardFrame = panel.frame.insetBy(dx: MiniPopupMetrics.shadowInset, dy: MiniPopupMetrics.shadowInset)
        let clickedCard = cardFrame.contains(point)
        let clickedChild = panel.childWindows?.contains { $0.frame.contains(point) } ?? false
        guard !clickedCard, !clickedChild else { return }
        dismiss()
    }

    private func registerHotKey(_ requestedShortcut: MiniPopupHotKey? = nil) -> Bool {
        guard hotKey == nil else { return true }
        let shortcut = requestedShortcut ?? BrowserStore.shared.settings.miniPopupHotKey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            miniPopupHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { return false }
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else {
            removeEventHandler()
            return false
        }
        return true
    }

    private func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        removeEventHandler()
    }

    private func removeEventHandler() {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func makePanel() -> MiniPopupPanel {
        let model = AppDelegate.shared.mainModel ?? WindowModel()
        let assistant = makeAssistant(for: model)
        self.model = model
        self.assistant = assistant

        let panel = MiniPopupPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        let hostingView = NSHostingView(rootView: miniPopupView(model: model, assistant: assistant))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
        return panel
    }

    private func miniPopupView(model: WindowModel, assistant: AssistantModel) -> MiniPopupView {
        MiniPopupView(
            model: model,
            assistant: assistant,
            onCardHeightChange: { [weak self] height in self?.updateCardHeight(height) },
            onNewConversation: { [weak self] in self?.startFreshConversation() },
            onContinueInBrowser: { [weak self] in self?.continueInBrowser() },
            onClose: { [weak self] in self?.dismiss() }
        )
    }

    private var panelSize: NSSize {
        NSSize(width: MiniPopupMetrics.cardWidth + MiniPopupMetrics.shadowInset * 2, height: cardHeight + MiniPopupMetrics.shadowInset * 2)
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panelSize
        let origin = NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + MiniPopupMetrics.bottomMargin - MiniPopupMetrics.shadowInset)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

@MainActor
private final class MiniPopupPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
