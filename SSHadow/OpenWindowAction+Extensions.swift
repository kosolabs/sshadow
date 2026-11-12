import AppKit
import SwiftUI

extension OpenWindowAction {
    @MainActor
    func inFront(id: String) {
        self(id: id)
        NSApp.bringWindowToFront(id: id)
    }

    @MainActor
    func inFront<Value: Codable & Hashable>(id: String, value: Value) {
        self(id: id, value: value)
        NSApp.bringWindowToFront(id: id)
    }
}

extension OpenSettingsAction {
    @MainActor
    func inFront() {
        self()
        NSApp.bringWindowToFront(id: "com_apple_SwiftUI_Settings_window")
    }
}

extension NSApplication {
    @MainActor
    fileprivate func bringWindowToFront(id: String) {
        activate()
        windows
            .first { $0.identifier?.rawValue.contains(id) == true }?
            .makeKeyAndOrderFront(nil)
    }
}
