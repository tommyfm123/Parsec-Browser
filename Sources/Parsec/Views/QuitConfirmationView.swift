import AppKit
import SwiftUI

enum QuitConfirmationMetrics {
    static let cardWidth: CGFloat = 448
    static let cardHeight: CGFloat = 188
    static let cardRadius: CGFloat = 16
    static let contentPadding: CGFloat = 20
    static let iconWellSize: CGFloat = 36
    static let buttonHeight: CGFloat = 32
    static let buttonSpacing: CGFloat = 8

    static var panelSize: NSSize {
        NSSize(width: cardWidth, height: cardHeight)
    }
}

@MainActor
enum QuitConfirmation {
    private static let escapeKeyCode: UInt16 = 53
    private static let confirmKey = "q"

    static private(set) var isPresented = false

    static func isConfirmed() -> Bool {
        guard !isPresented else { return false }
        isPresented = true
        defer { isPresented = false }
        let panel = makePanel()
        panel.makeKeyAndOrderFront(nil)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
        let response = NSApp.runModal(for: panel)
        if let monitor { NSEvent.removeMonitor(monitor) }
        panel.orderOut(nil)
        return response == .OK
    }

    private static func makePanel() -> QuitConfirmationPanel {
        let panel = QuitConfirmationPanel(contentRect: NSRect(origin: .zero, size: QuitConfirmationMetrics.panelSize))
        let hostingView = NSHostingView(rootView: QuitConfirmationView(onCancel: cancel, onConfirm: confirm))
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.setFrame(frame(for: panel.frame.size), display: false)
        return panel
    }

    private static func frame(for size: NSSize) -> NSRect {
        let visibleFrame = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: size)
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func confirm() {
        NSApp.stopModal(withCode: .OK)
    }

    private static func cancel() {
        NSApp.stopModal(withCode: .cancel)
    }

    private static func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == escapeKeyCode {
            cancel()
            return nil
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isConfirmShortcut = modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == confirmKey
        guard isConfirmShortcut else { return event }
        confirm()
        return nil
    }
}

@MainActor
private final class QuitConfirmationPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct QuitConfirmationView: View {
    private enum Copy {
        static let title = "¿Salir de Parsec?"
        static let message = "Se cerrarán todas las ventanas y se interrumpirán las tareas en curso."
        static let cancelTitle = "Cancelar"
        static let confirmTitle = "Salir"
        static let cancelShortcut = "Esc"
        static let confirmShortcut = "⌘Q"
        static let dialogLabel = "Salir de Parsec"
    }

    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewState private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        card
            .scaleEffect(showsCard ? 1 : 0.98)
            .opacity(showsCard ? 1 : 0)
            .onAppear(perform: reveal)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Copy.dialogLabel)
            .accessibilityAddTraits(.isModal)
    }

    private var showsCard: Bool { isVisible || reduceMotion }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuitMark()
            Text(Copy.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.primary)
                .padding(.top, 16)
            Text(Copy.message)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.55))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Spacer(minLength: 0)
            HStack(spacing: QuitConfirmationMetrics.buttonSpacing) {
                Spacer(minLength: 0)
                QuitActionButton(title: Copy.cancelTitle, shortcut: Copy.cancelShortcut, isDestructive: false, action: onCancel)
                QuitActionButton(title: Copy.confirmTitle, shortcut: Copy.confirmShortcut, isDestructive: true, action: onConfirm)
            }
        }
        .padding(QuitConfirmationMetrics.contentPadding)
        .frame(width: QuitConfirmationMetrics.cardWidth, height: QuitConfirmationMetrics.cardHeight, alignment: .topLeading)
        .background(cardFill, in: cardShape)
        .overlay(cardShape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: QuitConfirmationMetrics.cardRadius, style: .continuous)
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color(red: 0.145, green: 0.145, blue: 0.155) : .white
    }

    private func reveal() {
        guard !reduceMotion else { return }
        withAnimation(Motion.spring(reduceMotion: false)) { isVisible = true }
    }
}

private struct QuitMark: View {
    private static let glyphSize: CGFloat = 16

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05))
            ZStack {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1.25, dash: [1.55, 1.7]))
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Color.primary.opacity(0.82))
            .frame(width: Self.glyphSize, height: Self.glyphSize)
        }
        .frame(width: QuitConfirmationMetrics.iconWellSize, height: QuitConfirmationMetrics.iconWellSize)
        .accessibilityHidden(true)
    }
}

private struct QuitActionButton: View {
    private static let confirmRed = Color(red: 0.86, green: 0.22, blue: 0.24)
    private static let confirmRedHover = Color(red: 0.78, green: 0.18, blue: 0.2)

    let title: String
    let shortcut: String
    let isDestructive: Bool
    let action: () -> Void
    @ViewState private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                Text(shortcut)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 22, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(badgeFill))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.leading, 11)
            .padding(.trailing, 6)
            .frame(height: QuitConfirmationMetrics.buttonHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(border)
        }
        .buttonStyle(.plain)
        .onHover(perform: updateHover)
        .pointerStyle(.link)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        isDestructive ? .white : Color.primary.opacity(0.9)
    }

    private var fill: Color {
        guard isDestructive else {
            return isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03)
        }
        return isHovering ? Self.confirmRedHover : Self.confirmRed
    }

    private var badgeFill: Color {
        isDestructive ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(isDestructive ? 0 : 0.12), lineWidth: 1)
    }

    private func updateHover(_ hovering: Bool) {
        isHovering = hovering
    }
}
