import Common
import FileProvider
import Foundation

private let logger = Logger(category: "XPCBroker")

typealias EventLogger = Events<ContinuousClock>.Logger

protocol XPCBroker {
    func broker(exporting service: CoreService, log: EventLogger) async
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

    func broker(exporting service: CoreService, log: EventLogger) async {
        if case .connected = state { return }
        let task = start(service: service, log: log)
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
        log: EventLogger
    ) -> Task<Void, Never> {
        if case .brokering(let task) = state { task.cancel() }
        let task = Task { await connect(service: service, log: log) }
        state = .brokering(task)
        return task
    }

    private func connect(service: CoreService, log: EventLogger) async {
        while !Task.isCancelled {
            do {
                let connection = try await domain.service.fileProviderConnection()
                try await attach(connection, service: service, log: log)
                state = .connected(connection)
                logger.notice("XPC brokered: \(domain)")
                if let mismatch = extensionMismatch(
                    connected: connection.peerBundleUrl,
                    expected: extensionUrl
                ) {
                    logger.error(
                        "Wrong extension connected for \(domain): \(mismatch)"
                    )
                    log.warning("Wrong extension connected", detail: mismatch)
                }
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
        service: CoreService,
        log: EventLogger
    ) async throws {
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            Task {
                guard let self else { return }
                await self.invalidated(connection, service: service, log: log)
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
        log: EventLogger
    ) {
        switch state {
        case .connected(let current) where current === connection: break
        case .brokering: break
        case .connected, .disconnected: return
        }
        logger.notice("XPC invalidated: \(domain)")
        start(service: service, log: log)
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

func extensionMismatch(connected url: URL?, expected: URL) -> String? {
    guard let url,
        url.resolvingSymlinksInPath().pathComponents
            != expected.resolvingSymlinksInPath().pathComponents
    else {
        return nil
    }
    return "connected \(url.path(percentEncoded: false)), "
        + "expected \(expected.path(percentEncoded: false))"
}

extension NSXPCConnection {
    fileprivate var peerBundleUrl: URL? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(processIdentifier, &path, UInt32(path.count)) > 0 else {
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
}
