import Common
import FileProvider

private let logger = Logger(category: "DomainXPCBroker")

@MainActor
public final class DomainXPCBroker {
    public static let shared = DomainXPCBroker()

    private var connections: [UUID: NSXPCConnection] = [:]

    public func broker(_ domain: NSFileProviderDomain) async throws {
        await teardown(domainId: domain.id)
        try await domain.resume()

        let connection = try await requireConnection(for: domain)

        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = CoreService.shared
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            logger.info("Invalidated XPC: \(domain.id)")
            Task { @MainActor in
                guard let self else { return }
                self.connections[domain.id] = nil
                do {
                    try await self.broker(domain)
                } catch {
                    logger.error(
                        "Failed to broker XPC for \(domain.id): \(error)"
                    )
                    return
                }
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()

        connections[domain.id] = connection

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()

        logger.info("Brokered XPC: \(domain.id)")
    }

    private func requireConnection(
        for domain: NSFileProviderDomain
    ) async throws -> NSXPCConnection {
        while true {
            do {
                return try await domain.service.fileProviderConnection()
            } catch {
                logger.error(
                    "Failed to broker XPC for \(domain.id): \(error)"
                )
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func teardown(domainId: UUID) async {
        guard let connection = connections.removeValue(forKey: domainId) else {
            return
        }
        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.detach()
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
        logger.info("Tore down XPC: \(domainId)")
    }
}
