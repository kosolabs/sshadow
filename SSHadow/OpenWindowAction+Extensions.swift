import AppKit
import SwiftUI

extension OpenWindowAction {
    @MainActor
    func inFront(id: String) {
        self(id: id)
        NSApp.activate()
        NSApp.windows
            .first { $0.identifier?.rawValue.contains(id) == true }?
            .makeKeyAndOrderFront(nil)
    }
}
