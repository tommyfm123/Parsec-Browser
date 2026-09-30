import AppKit

@MainActor
extension NSWindow {
    static let trafficLightButtonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    func positionTrafficLights(centerY: CGFloat, leadingInset: CGFloat) {
        let buttons = Self.trafficLightButtonTypes.compactMap(standardWindowButton)
        guard centerY > 0, !styleMask.contains(.fullScreen), let firstButton = buttons.first,
              let titlebarContainer = firstButton.superview?.superview else { return }
        let buttonHeight = firstButton.frame.height
        let containerHeight = centerY + buttonHeight / 2 + 4
        titlebarContainer.frame = NSRect(x: titlebarContainer.frame.minX, y: frame.height - containerHeight, width: titlebarContainer.frame.width, height: containerHeight)
        firstButton.superview?.frame = titlebarContainer.bounds
        let spacing = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.minX : 20
        let originY = containerHeight - centerY - buttonHeight / 2
        for (index, button) in buttons.enumerated() {
            button.setFrameOrigin(NSPoint(x: leadingInset + CGFloat(index) * spacing, y: originY))
        }
    }
}
