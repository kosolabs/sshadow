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
    // One per extension process. File Provider can run more than one for a
    // domain, for example while it replaces an instance.
    private var connections: [NSXPCConnection] = []
    private var service: CoreService?
    private var rebrokering: Task<Void, Never>?
    private var connectRequests: DarwinNotification.Observer?

    init(domain: NSFileProviderDomain) {
        self.domain = domain
    }

    func broker(exporting service: CoreService) async {
        self.service = service
        connectRequests = DarwinNotification.Observer(
            SSHadow.connectRequest(domainId: domain.identifier.rawValue)
        ) { [weak self] in
            Task { await self?.connectRequested() }
        }
        await broker()
    }

    private func broker() async {
        guard connections.isEmpty else { return }
        await connect()
    }

    /// An extension instance without a connection asked for one. Look up the
    /// service again, which may reach that instance.
    private func connectRequested() async {
        guard connectRequests != nil, !connections.isEmpty else { return }
        logger.info("Extension requested XPC: \(domain)")
        await connect()
    }

    private func connect() async {
        guard let connection = await awaitConnection() else { return }

        let id = ObjectIdentifier(connection)
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            Task { await self?.invalidated(id) }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()
        guard !Task.isCancelled, connectRequests != nil else {
            invalidate(connection)
            return
        }

        // The extension only uses its newest connection, so replace any
        // existing connection to the same process.
        let pid = connection.processIdentifier
        if let index = connections.firstIndex(where: {
            $0.processIdentifier == pid
        }) {
            invalidate(connections[index])
            connections[index] = connection
        } else {
            connections.append(connection)
        }

        logger.notice("XPC brokered: \(domain), pid: \(pid)")
    }

    private func awaitConnection() async -> NSXPCConnection? {
        while !Task.isCancelled {
            do {
                return try await domain.service.fileProviderConnection()
            } catch {
                logger.error("Failed to broker XPC for \(domain): \(error)")
                try? await Task.sleep(for: .seconds(1))
            }
        }
        return nil
    }

    private func invalidated(_ id: ObjectIdentifier) {
        guard
            let index = connections.firstIndex(where: {
                ObjectIdentifier($0) == id
            })
        else { return }
        connections.remove(at: index)
        logger.notice("XPC invalidated: \(domain)")

        guard connections.isEmpty, connectRequests != nil else { return }
        rebrokering = Task { await broker() }
    }

    func teardown() async {
        connectRequests = nil
        if let rebrokering {
            rebrokering.cancel()
            await rebrokering.value
            self.rebrokering = nil
        }
        let connections = self.connections
        self.connections = []
        guard !connections.isEmpty else { return }

        for connection in connections {
            let ext = connection.remoteObjectProxy as! ExtXPC
            await ext.detach()
            invalidate(connection)
        }

        logger.notice("XPC torn down: \(domain)")
    }

    private func invalidate(_ connection: NSXPCConnection) {
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
    }
}
