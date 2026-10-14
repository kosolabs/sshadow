import Foundation
import Synchronization

extension NSXPCConnection {
    public typealias Reply<T> = @Sendable (Result<T, any Error>) -> Void

    public func call<Proxy, T: Sendable>(
        _ body: (Proxy, @escaping Reply<T>) -> Void
    ) async throws -> T {
        try Task.checkCancellation()
        let once = OnceContinuation<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.wait(continuation)
                let proxy = remoteObjectProxyWithErrorHandler { error in
                    once.resume(with: .failure(error))
                }
                body(proxy as! Proxy) { once.resume(with: $0) }
            }
        } onCancel: {
            once.resume(with: .failure(CancellationError()))
        }
    }
}

private final class OnceContinuation<T: Sendable>: Sendable {
    private enum State {
        case pending
        case waiting(CheckedContinuation<T, any Error>)
        case resolved(Result<T, any Error>)
        case finished
    }

    private let state = Mutex(State.pending)

    func wait(_ continuation: CheckedContinuation<T, any Error>) {
        let result: Result<T, any Error>? = state.withLock {
            switch $0 {
            case .pending:
                $0 = .waiting(continuation)
                return nil
            case .resolved(let result):
                $0 = .finished
                return result
            case .waiting, .finished:
                preconditionFailure("Continuation already set")
            }
        }
        if let result { continuation.resume(with: result) }
    }

    func resume(with result: Result<T, any Error>) {
        let continuation: CheckedContinuation<T, any Error>? = state.withLock {
            switch $0 {
            case .pending:
                $0 = .resolved(result)
                return nil
            case .waiting(let continuation):
                $0 = .finished
                return continuation
            case .resolved, .finished:
                return nil
            }
        }
        continuation?.resume(with: result)
    }
}
