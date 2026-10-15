import Common
import FileProvider
import Foundation

private let logger = Logger(category: "XPCBroker")

protocol XPCBroker {
    func broker(exporting service: CoreService) async
    func teardown() async
}

actor DomainXPCBroker: XPCBroker {
    private let domain: NSFileProviderDomain

    private enum State {
        case disconnected
        case brokering(Task<Void, Never>)
        case connected(NSXPCConnection)
    }
    private var state: State = .disconnected

    init(domain: NSFileProviderDomain) {
        self.domain = domain
    }

    func broker(exporting service: CoreService) async {
        if case .connected = state { return }
        let task = start(service: service)
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if case .brokering(let current) = state, current == task {
            state = .disconnected
        }
    }

    @discardableResult
    private func start(service: CoreService) -> Task<Void, Never> {
        if case .brokering(let task) = state { task.cancel() }
        let task = Task { await connect(service: service) }
        state = .brokering(task)
        return task
    }

    private func connect(service: CoreService) async {
        while !Task.isCancelled {
            do {
                let connection = try await domain.service.fileProviderConnection()
                try await attach(connection, service: service)
                state = .connected(connection)
                logger.notice("XPC brokered: \(domain)")
                return
            } catch where Task.isCancelled {
                return
            } catch let error as NSError where error.isDisconnectedDomain {
                logger.error(
                    "Failed to broker XPC for \(domain), reconnecting: \(error)"
                )
                await domain.resume()
            } catch {
                logger.error("Failed to broker XPC for \(domain): \(error)")
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func attach(
        _ connection: NSXPCConnection,
        service: CoreService
    ) async throws {
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            Task {
                guard let self else { return }
                await self.invalidated(connection, service: service)
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()
        do {
            try await connection.attach()
            try Task.checkCancellation()
        } catch {
            invalidate(connection)
            throw error
        }
    }

    private func invalidated(
        _ connection: NSXPCConnection,
        service: CoreService
    ) {
        switch state {
        case .connected(let current) where current === connection: break
        case .brokering: break
        case .connected, .disconnected: return
        }
        logger.notice("XPC invalidated: \(domain)")
        start(service: service)
    }

    func teardown() async {
        let previous = state
        state = .disconnected
        switch previous {
        case .disconnected:
            break
        case .brokering(let task):
            task.cancel()
            await task.value
            logger.notice("XPC cancelled: \(domain)")
        case .connected(let connection):
            do {
                try await connection.detach()
            } catch {
                logger.error("Failed to detach XPC for \(domain): \(error)")
            }
            invalidate(connection)
            logger.notice("XPC torn down: \(domain)")
        }
    }

    private func invalidate(_ connection: NSXPCConnection) {
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
    }
}

extension NSError {
    // Seen when brokering to a disconnected domain; the underlying code isn't public.
    fileprivate var isDisconnectedDomain: Bool {
        guard domain == NSCocoaErrorDomain,
            code == NSXPCConnectionReplyInvalid,
            let underlying = userInfo[NSUnderlyingErrorKey] as? NSError
        else {
            return false
        }
        return underlying.domain == "NSFileProviderInternalErrorDomain"
            && underlying.code == 12
    }
}
