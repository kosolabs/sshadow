import Foundation
import Synchronization

/// A `Clock` whose `sleep(until:)` calls only complete once the test advances it
/// past their deadline, enabling deterministic coalescing/throttle tests.
final class TestClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Int: Sleeper] = [:]
        var nextID = 0
    }

    private let state = Mutex(State())

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration { .zero }

    /// The number of `sleep(until:)` calls currently suspended, awaiting an advance.
    var pendingCount: Int {
        state.withLock { $0.sleepers.count }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { s -> Int in
            defer { s.nextID += 1 }
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enum Immediate { case park, resume, cancel }
                let action = state.withLock { s -> Immediate in
                    if Task.isCancelled { return .cancel }
                    if deadline <= s.now { return .resume }
                    s.sleepers[id] = Sleeper(
                        deadline: deadline,
                        continuation: continuation
                    )
                    return .park
                }
                switch action {
                case .park: break
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let sleeper = state.withLock { $0.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Advances `now` by `duration`, resuming every sleep whose deadline has passed.
    func advance(by duration: Duration) {
        let due = state.withLock { s -> [CheckedContinuation<Void, any Error>] in
            s.now = s.now.advanced(by: duration)
            let now = s.now
            let ready = s.sleepers.filter { $0.value.deadline <= now }
            for id in ready.keys {
                s.sleepers.removeValue(forKey: id)
            }
            return ready.values.map(\.continuation)
        }
        for continuation in due {
            continuation.resume()
        }
    }
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline { return }
        await Task.yield()
    }
}
