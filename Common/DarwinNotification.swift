import Foundation

/// Darwin notifications reach every process of the user, including sandboxed
/// ones, which makes them a way for the extension to signal the app. They
/// carry no payload.
public enum DarwinNotification {
    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    /// Calls `handler`, on an arbitrary thread, each time `name` is posted,
    /// until the observer is deallocated.
    public final class Observer: Sendable {
        private let handler: @Sendable () -> Void

        public init(_ name: String, handler: @escaping @Sendable () -> Void) {
            self.handler = handler
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<Observer>.fromOpaque(observer)
                        .takeUnretainedValue()
                        .handler()
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }

        deinit {
            CFNotificationCenterRemoveEveryObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }
}
