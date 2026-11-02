import Testing

@testable import CoreKit

@MainActor
private final class Latch {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}

@MainActor
private func settle() async {
    for _ in 0..<100 {
        await Task.yield()
    }
}

private struct Failure: Error {}

@MainActor
struct AsyncLockTests {
    let lock = AsyncLock()

    @Test func waitsForTheHolder() async {
        var events: [String] = []
        let latch = Latch()
        let first = Task {
            await lock.withLock {
                events.append("first")
                await latch.wait()
            }
        }
        await settle()

        let second = Task { await lock.withLock { events.append("second") } }
        await settle()
        #expect(events == ["first"])

        latch.open()
        await first.value
        await second.value
        #expect(events == ["first", "second"])
    }

    @Test func runsWaitersInOrder() async {
        var events: [Int] = []
        let latch = Latch()
        let holder = Task { await lock.withLock { await latch.wait() } }
        await settle()

        var waiters: [Task<Void, Never>] = []
        for i in 0..<3 {
            waiters.append(Task { await lock.withLock { events.append(i) } })
            await settle()
        }

        latch.open()
        await holder.value
        for waiter in waiters {
            await waiter.value
        }
        #expect(events == [0, 1, 2])
    }

    @Test func releasesWhenTheBodyThrows() async {
        await #expect(throws: Failure.self) {
            try await lock.withLock { throw Failure() }
        }

        var ran = false
        await lock.withLock { ran = true }
        #expect(ran)
    }
}
