final class ReconcileGate {
    private(set) var operations = 0
    private var reconciling = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isBusy: Bool { operations > 0 || reconciling }

    func enter(isolation: isolated (any Actor)? = #isolation) async {
        operations += 1
        while reconciling {
            await wait()
        }
    }

    func leave() {
        operations -= 1
        if operations == 0 {
            wake()
        }
    }

    func reconcile<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        while isBusy {
            await wait()
        }
        reconciling = true
        defer {
            reconciling = false
            wake()
        }
        return try await body()
    }

    private func wait(isolation: isolated (any Actor)? = #isolation) async {
        await withCheckedContinuation { waiters.append($0) }
    }

    private func wake() {
        let waiters = waiters
        self.waiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }
}
