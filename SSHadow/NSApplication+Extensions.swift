import AppKit

extension NSApplication {
    private var statusItems: [NSStatusItem] {
        windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
    }

    func dismissMenuBarExtra() {
        if #available(macOS 27.0, *) {
            for session in statusItems.compactMap(\.expandedInterfaceSession) {
                session.cancel()
            }
            return
        }
        guard let button = statusItems.lazy.compactMap(\.button).first else { return }
        button.performClick(button)
        button.isHighlighted = false
    }
}
