import AppKit

ColorfulWindowControls.enable()
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    application.setActivationPolicy(.regular)
    withExtendedLifetime(appDelegate) {
        application.run()
    }
}
