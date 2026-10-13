import Foundation
import Synchronization
import Testing

@testable import Common

struct DarwinNotificationTests {
    /// Darwin notifications are delivered on the main run loop, so wait without
    /// blocking it.
    private func wait(
        until condition: () -> Bool,
        timeout: Duration = .seconds(5)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func observerIsCalledForEachPost() async throws {
        let name = "\(SSHadow.appGroup).test.\(UUID().uuidString)"
        let count = Mutex(0)
        let observer = DarwinNotification.Observer(name) {
            count.withLock { $0 += 1 }
        }

        DarwinNotification.post(name)
        try await wait { count.withLock { $0 } == 1 }
        DarwinNotification.post(name)
        try await wait { count.withLock { $0 } == 2 }

        #expect(count.withLock { $0 } == 2)
        withExtendedLifetime(observer) {}
    }

    @Test func observerIsNotCalledAfterRelease() async throws {
        let name = "\(SSHadow.appGroup).test.\(UUID().uuidString)"
        let count = Mutex(0)
        var observer: DarwinNotification.Observer? =
            DarwinNotification.Observer(name) {
                count.withLock { $0 += 1 }
            }
        DarwinNotification.post(name)
        try await wait { count.withLock { $0 } == 1 }

        observer = nil
        DarwinNotification.post(name)
        try await Task.sleep(for: .milliseconds(200))

        #expect(observer == nil)
        #expect(count.withLock { $0 } == 1)
    }
}
