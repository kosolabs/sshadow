import Common
import FileProvider
import Foundation

private let logger = Logger(category: "XPCBroker")

typealias UnreachableHandler = @Sendable (_ otherExtension: URL?) -> Void

protocol XPCBroker {
    func broker(
        exporting service: CoreService,
        onUnreachable: @escaping UnreachableHandler
    ) async
    func ready() async
    func teardown() async
}

actor DomainXPCBroker: XPCBroker {
    private let domain: NSFileProviderDomain
    private let extensionUrl: URL

    private enum State {
        case disconnected
        case brokering(Task<Void, Never>)
        case connected(NSXPCConnection)
    }
    private var state: State = .disconnected

    init(domain: NSFileProviderDomain, extensionUrl: URL) {
        self.domain = domain
        self.extensionUrl = extensionUrl
    }

    func broker(
        exporting service: CoreService,
        onUnreachable: @escaping UnreachableHandler
    ) async {
        if case .connected = state { return }
        let task = start(service: service, onUnreachable: onUnreachable)
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
    private func start(
        service: CoreService,
        onUnreachable: @escaping UnreachableHandler
    ) -> Task<Void, Never> {
        if case .brokering(let task) = state { task.cancel() }
        let task = Task {
            await connect(service: service, onUnreachable: onUnreachable)
        }
        state = .brokering(task)
        return task
    }

    private func connect(
        service: CoreService,
        onUnreachable: @escaping UnreachableHandler
    ) async {
        while !Task.isCancelled {
            do {
                let connection = try await domain.service
                    .fileProviderConnection()
                try await attach(
                    connection,
                    service: service,
                    onUnreachable: onUnreachable
                )
                if let other = wrongExtension(
                    connected: connection.peerBundleUrl,
                    expected: extensionUrl
                ) {
                    invalidate(connection)
                    logger.error(
                        "Refused extension for \(domain) from "
                            + "\(other.path(percentEncoded: false)), expected "
                            + "\(extensionUrl.path(percentEncoded: false))"
                    )
                    onUnreachable(other)
                    return
                }
                state = .connected(connection)
                logger.notice("XPC brokered: \(domain)")
                return
            } catch  where Task.isCancelled {
                return
            } catch let error as NSError where error.isDisconnectedDomain {
                logger.error(
                    "Failed to broker XPC for \(domain), reconnecting: \(error)"
                )
                await domain.resume()
            } catch let error as NSError where error.isFileProviderRestart {
                logger.error(
                    "Failed to broker XPC for \(domain), retrying: \(error)"
                )
            } catch {
                logger.error("Failed to broker XPC for \(domain): \(error)")
                onUnreachable(nil)
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func attach(
        _ connection: NSXPCConnection,
        service: CoreService,
        onUnreachable: @escaping UnreachableHandler
    ) async throws {
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            Task {
                guard let self else { return }
                await self.invalidated(
                    connection,
                    service: service,
                    onUnreachable: onUnreachable
                )
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
        service: CoreService,
        onUnreachable: @escaping UnreachableHandler
    ) {
        switch state {
        case .connected(let current) where current === connection: break
        case .brokering: break
        case .connected, .disconnected: return
        }
        logger.notice("XPC invalidated: \(domain)")
        let task = start(service: service, onUnreachable: onUnreachable)
        Task {
            await task.value
            await ready()
        }
    }

    func ready() async {
        guard case .connected(let connection) = state else { return }
        do {
            try await connection.ready()
        } catch {
            logger.error("Failed to signal ready to \(domain): \(error)")
        }
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

func wrongExtension(connected url: URL?, expected: URL) -> URL? {
    guard let url,
        url.resolvingSymlinksInPath().pathComponents
            != expected.resolvingSymlinksInPath().pathComponents
    else {
        return nil
    }
    return url
}

extension NSXPCConnection {
    fileprivate var peerBundleUrl: URL? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(processIdentifier, &path, UInt32(path.count)) > 0
        else {
            logger.error(
                "Failed to find the path of pid \(processIdentifier): errno \(errno)"
            )
            return nil
        }
        // .../Extension.appex/Contents/MacOS/Extension
        return URL(filePath: String(cString: path))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

extension URL {
    static let builtInExtension = Bundle.main.builtInPlugInsURL!
        .appending(path: "Extension.appex")
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

    // Seen when fileproviderd exits while brokering.
    fileprivate var isFileProviderRestart: Bool {
        domain == NSCocoaErrorDomain && code == NSXPCConnectionInvalid
    }
}
