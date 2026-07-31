import Common
import FileProvider
import Foundation

private let logger = Logger(category: "DomainLink")

/// Per-domain owner of the `NSXPCConnection` to the File Provider extension: it
/// brokers the connection (exporting the core service and attaching the
/// extension), re-brokers on invalidation, and tears it down. This is the
/// supervisor's main-actor arm and absorbs the old `DomainXPCBroker` — one
/// instance per domain rather than a singleton holding a dictionary.
///
/// The domain-facing steps (`resume`, `connect`) are injectable so the link can
/// be exercised without a live File Provider domain; production wires them to
/// `NSFileProviderManager`.
@MainActor
final class DomainLink {
    typealias Connect = @Sendable () async throws -> NSXPCConnection

    private let domain: NSFileProviderDomain
    private let exportedObject: any CoreXPC
    private let resume: @Sendable () async throws -> Void
    private let connect: Connect

    private var connection: NSXPCConnection?

    nonisolated init(
        domain: NSFileProviderDomain,
        exportedObject: any CoreXPC = CoreService.shared,
        resume: (@Sendable () async throws -> Void)? = nil,
        connect: Connect? = nil
    ) {
        self.domain = domain
        self.exportedObject = exportedObject
        self.resume = resume ?? { try await domain.resume() }
        self.connect =
            connect ?? { try await domain.service.fileProviderConnection() }
    }

    /// (Re)establishes the XPC link: resumes the domain, connects, exports the
    /// core service, and attaches the extension. Tears down any existing
    /// connection first, so it is safe to call repeatedly.
    func broker() async throws {
        await teardown()
        try await resume()

        let domainId = domain.id
        let connection = try await requireConnection()
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = exportedObject
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            logger.info("Invalidated XPC: \(domainId)")
            Task { @MainActor in
                guard let self else { return }
                self.connection = nil
                do {
                    try await self.broker()
                } catch {
                    logger.error(
                        "Failed to broker XPC for \(domainId): \(error)"
                    )
                }
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()
        self.connection = connection

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()

        logger.info("Brokered XPC: \(domainId)")
    }

    private func requireConnection() async throws -> NSXPCConnection {
        while true {
            do {
                return try await connect()
            } catch {
                logger.error(
                    "Failed to broker XPC for \(domain.id): \(error)"
                )
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Detaches the extension and invalidates the connection. Clears the
    /// handlers first so the intentional invalidation does not trigger a
    /// re-broker. A no-op when there is no live connection.
    func teardown() async {
        guard let connection else { return }
        self.connection = nil

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.detach()
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()

        logger.info("Tore down XPC: \(domain.id)")
    }
}
