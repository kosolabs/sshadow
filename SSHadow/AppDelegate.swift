import AppKit
import Common

private let logger = Logger(category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let testCommands = TestCommands.enabled ? TestCommands() : nil

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            logger.notice("Opened file: \(url.path(percentEncoded: false))")
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        OpensRequestedWindows.request(id: "connections")
        return false
    }
}
