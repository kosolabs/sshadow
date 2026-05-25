import AppKit

extension NSApplication {
    func dismissMenuBarExtra() {
        let statusBarWindow = windows.first {
            $0.className.contains("NSStatusBarWindow")
        }
        guard let item = statusBarWindow?.value(forKey: "statusItem") as? NSStatusItem,
            let button = item.button
        else { return }
        button.performClick(button)
        button.isHighlighted = button.state != .off
    }
}
