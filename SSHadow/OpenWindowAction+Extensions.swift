import AppKit
import SwiftUI

extension OpenWindowAction {
    @MainActor
    func inFront(id: String) {
        self(id: id)
        bringToFront(id: id)
    }

    @MainActor
    func inFront<Value: Codable & Hashable>(id: String, value: Value) {
        self(id: id, value: value)
        bringToFront(id: id)
    }

    @MainActor
    private func bringToFront(id: String) {
        NSApp.activate()
        NSApp.windows
            .first { $0.identifier?.rawValue.contains(id) == true }?
            .makeKeyAndOrderFront(nil)
    }
}
