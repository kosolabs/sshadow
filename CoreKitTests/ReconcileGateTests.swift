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

@MainActor
struct ReconcileGateTests {
    let gate = ReconcileGate()

    @Test func operationsRunTogether() async {
        await gate.enter()
        await gate.enter()
        #expect(gate.operations == 2)
        #expect(gate.isBusy)

        gate.leave()
        gate.leave()
        #expect(gate.operations == 0)
        #expect(!gate.isBusy)
    }

    @Test func reconcileWaitsForOperations() async {
        var events: [String] = []
        await gate.enter()

        let reconcile = Task { await gate.reconcile { events.append("reconcile") } }
        await settle()
        #expect(events.isEmpty)

        events.append("leave")
        gate.leave()
        await reconcile.value
        #expect(events == ["leave", "reconcile"])
    }

    @Test func operationWaitsForReconcile() async {
        var events: [String] = []
        let latch = Latch()

        let reconcile = Task {
            await gate.reconcile {
                await latch.wait()
                events.append("reconcile")
            }
        }
        await settle()

        let operation = Task {
            await gate.enter()
            events.append("operation")
            gate.leave()
        }
        await settle()
        #expect(events.isEmpty)

        latch.open()
        await reconcile.value
        await operation.value
        #expect(events == ["reconcile", "operation"])
    }

    @Test func reconcilesRunOneAtATime() async {
        var events: [String] = []
        let latch = Latch()

        let first = Task {
            await gate.reconcile {
                events.append("first start")
                await latch.wait()
                events.append("first end")
            }
        }
        await settle()

        let second = Task { await gate.reconcile { events.append("second") } }
        await settle()
        #expect(events == ["first start"])

        latch.open()
        await first.value
        await second.value
        #expect(events == ["first start", "first end", "second"])
    }

    @Test func waitingOperationGoesBeforeWaitingReconcile() async {
        var events: [String] = []
        let first = Latch()
        let operating = Latch()

        let running = Task {
            await gate.reconcile {
                await first.wait()
                events.append("first")
            }
        }
        await settle()

        let operation = Task {
            await gate.enter()
            events.append("operation start")
            await operating.wait()
            events.append("operation end")
            gate.leave()
        }
        let waiting = Task { await gate.reconcile { events.append("second") } }
        await settle()

        first.open()
        await running.value
        await settle()
        #expect(events == ["first", "operation start"])

        operating.open()
        await operation.value
        await waiting.value
        #expect(events == ["first", "operation start", "operation end", "second"])
    }

    @Test func reconcileReleasesGateWhenItThrows() async {
        struct Failure: Error {}

        await #expect(throws: Failure.self) {
            try await gate.reconcile { throw Failure() }
        }
        #expect(!gate.isBusy)

        await gate.enter()
        gate.leave()
    }
}
