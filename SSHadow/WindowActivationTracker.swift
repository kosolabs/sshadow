import AppKit
import Foundation

@Observable
final class WindowActivationTracker {
    private var count = 0

    func retain() {
        count += 1
        if count == 1 {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
    }

    func release() {
        count -= 1
        if count == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
