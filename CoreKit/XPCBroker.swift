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
    private var connection: NSXPCConnection?
    private var rebrokering: Task<Void, Never>?

    init(domain: NSFileProviderDomain) {
        self.domain = domain
    }

    func broker(exporting service: CoreService) async {
        await broker(service: service)
    }

    private func broker(service: CoreService) async {
        guard connection == nil, let connection = await awaitConnection() else {
            return
        }

        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            Task {
                guard let self else { return }
                await self.rebrokerXpc(service: service)
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()
        guard !Task.isCancelled else {
            invalidate(connection)
            return
        }
        self.connection = connection

        logger.notice("XPC brokered: \(domain)")
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

    private func rebrokerXpc(service: CoreService) {
        logger.notice("XPC invalidated: \(domain)")
        connection = nil
        rebrokering = Task { await broker(service: service) }
    }

    func teardown() async {
        if let rebrokering {
            rebrokering.cancel()
            await rebrokering.value
            self.rebrokering = nil
        }
        guard let connection else { return }
        self.connection = nil

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.detach()
        invalidate(connection)

        logger.notice("XPC torn down: \(domain)")
    }
    
    private func invalidate(_ connection: NSXPCConnection) {
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
    }
}
