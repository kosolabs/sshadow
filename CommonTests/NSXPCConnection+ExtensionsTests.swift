import Foundation
import Synchronization
import Testing

@testable import Common

private final class StubExt: NSObject, ExtXPC {
    let replies: Bool
    let (called, calledContinuation) = AsyncStream<Void>.makeStream()

    init(replies: Bool) {
        self.replies = replies
    }

    func attach(reply: @escaping @Sendable () -> Void) {
        calledContinuation.yield()
        if replies { reply() }
    }

    func detach(reply: @escaping @Sendable () -> Void) {
        reply()
    }
}

private final class StubCore: NSObject, CoreXPC {
    let (called, calledContinuation) = AsyncStream<Void>.makeStream()

    func handle(
        _ data: Data,
        reply: @escaping @Sendable (Data?, (any Error)?) -> Void
    ) {
        calledContinuation.yield()
    }

    func handle(
        _ data: Data,
        progressEndpoint: NSXPCListenerEndpoint,
        reply: @escaping @Sendable (Data?, (any Error)?) -> Void
    ) {
        calledContinuation.yield()
    }
}

private final class Server: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener.anonymous()
    private let interface: NSXPCInterface
    private let exported: AnyObject
    private let accepted = Mutex<NSXPCConnection?>(nil)

    init(_ proto: Protocol, exporting exported: AnyObject) {
        self.interface = NSXPCInterface(with: proto)
        self.exported = exported
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = interface
        connection.exportedObject = exported
        connection.resume()
        accepted.withLock { $0 = connection }
        return true
    }

    func connect() -> NSXPCConnection {
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = interface
        connection.resume()
        return connection
    }

    func invalidate() {
        accepted.withLock { $0?.invalidate() }
    }
}

private struct Pending<T: Sendable> {
    let task: Task<Void, Never>
    let results: AsyncStream<Result<T, any Error>>

    init(_ body: sending @escaping () async throws -> T) {
        let (results, continuation) = AsyncStream<Result<T, any Error>>
            .makeStream()
        self.results = results
        self.task = Task {
            do {
                continuation.yield(.success(try await body()))
            } catch {
                continuation.yield(.failure(error))
            }
        }
    }

    func result(
        within timeout: Duration = .seconds(3)
    ) async -> Result<T, any Error>? {
        await withTaskGroup(of: Result<T, any Error>?.self) { group in
            group.addTask {
                for await result in results { return result }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }
}

private func waitFor(_ stream: AsyncStream<Void>) async {
    for await _ in stream { return }
}

struct NSXPCConnectionExtensionsTests {
    @Test func attachReturnsWhenReplied() async throws {
        let ext = StubExt(replies: true)
        let server = Server(ExtXPC.self, exporting: ext)
        let connection = server.connect()

        let pending = Pending { try await connection.attach() }

        let result = try #require(await pending.result())
        #expect(throws: Never.self) { try result.get() }
    }

    @Test func attachThrowsWhenServerInvalidates() async throws {
        let ext = StubExt(replies: false)
        let server = Server(ExtXPC.self, exporting: ext)
        let connection = server.connect()

        let pending = Pending { try await connection.attach() }
        await waitFor(ext.called)
        server.invalidate()

        let result = try #require(await pending.result())
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test func attachThrowsWhenClientInvalidates() async throws {
        let ext = StubExt(replies: false)
        let server = Server(ExtXPC.self, exporting: ext)
        let connection = server.connect()

        let pending = Pending { try await connection.attach() }
        await waitFor(ext.called)
        connection.invalidate()

        let result = try #require(await pending.result())
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test func attachThrowsWhenCancelled() async throws {
        let ext = StubExt(replies: false)
        let server = Server(ExtXPC.self, exporting: ext)
        let connection = server.connect()

        let pending = Pending { try await connection.attach() }
        await waitFor(ext.called)
        pending.task.cancel()

        let result = try #require(await pending.result())
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test func handleThrowsWhenServerInvalidates() async throws {
        let core = StubCore()
        let server = Server(CoreXPC.self, exporting: core)
        let connection = server.connect()

        let pending = Pending { try await connection.handle(Data()) }
        await waitFor(core.called)
        server.invalidate()

        let result = try #require(await pending.result())
        #expect(throws: (any Error).self) { try result.get() }
    }
}
