import Common
import FileProvider

private let logger = Logger(category: "DomainXPCBroker")

@MainActor
public final class DomainXPCBroker {
    public static let shared = DomainXPCBroker()

    private var connections: [UUID: NSXPCConnection] = [:]

    public func broker(_ domain: NSFileProviderDomain) async {
        teardown(domainId: domain.id)

        let connection: NSXPCConnection
        do {
            connection = try await domain.service.fileProviderConnection()
        } catch {
            // TODO: Look in to rebrokering failed to broker connections
            logger.error("Failed to broker XPC for \(domain.id): \(error)")
            return
        }

        connection.exportedInterface = NSXPCInterface(with: AppXPC.self)
        connection.exportedObject = AppService.shared
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            logger.info("Invalidated XPC: \(domain.id)")
            Task { @MainActor in
                guard let self else { return }
                self.connections[domain.id] = nil
                await self.broker(domain)
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()

        connections[domain.id] = connection

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.broker()

        logger.info("Brokered XPC: \(domain.id)")
    }

    public func teardown(domainId: UUID) {
        guard let connection = connections.removeValue(forKey: domainId) else {
            return
        }
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
        logger.info("Tore Down XPC: \(domainId)")
    }
}
