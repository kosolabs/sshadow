import Common
import FileProvider
import Foundation

private let logger = Logger(category: "DomainLink")

/// Per-domain owner of the `NSXPCConnection` to the File Provider extension: it
/// brokers the connection (exporting the core service and attaching the
/// extension), re-brokers on invalidation, and tears it down. It is also the
/// supervisor's main-actor "hands" for suspending and resuming the domain — but
/// only the mechanism. The supervisor decides *when* to suspend or resume; this
/// class never touches domain connection state on its own. Absorbs the old
/// `DomainXPCBroker` — one instance per domain rather than a singleton holding a
/// dictionary.
///
/// The domain-facing steps (`connect`, `suspend`, `resume`) are injectable so
/// the link can be exercised without a live File Provider domain; production
/// wires them to `NSFileProviderManager`.
@MainActor
final class DomainLink {
    typealias Connect = @Sendable () async throws -> NSXPCConnection

    private let domain: NSFileProviderDomain
    private let exportedObject: any CoreXPC
    private let connect: Connect
    private let suspendDomain: @Sendable (String) async throws -> Void
    private let resumeDomain: @Sendable () async throws -> Void

    private var connection: NSXPCConnection?

    /// Invoked after every successful broker (including automatic re-brokers on
    /// invalidation), so the supervisor can gate a resume on composite health.
    private var onBrokered: (@Sendable () async -> Void)?

    nonisolated init(
        domain: NSFileProviderDomain,
        exportedObject: any CoreXPC = CoreService.shared,
        connect: Connect? = nil,
        suspend: (@Sendable (String) async throws -> Void)? = nil,
        resume: (@Sendable () async throws -> Void)? = nil
    ) {
        self.domain = domain
        self.exportedObject = exportedObject
        self.connect =
            connect ?? { try await domain.service.fileProviderConnection() }
        self.suspendDomain =
            suspend ?? { reason in
                try await domain.suspend(reason: reason, options: .temporary)
            }
        self.resumeDomain = resume ?? { try await domain.resume() }
    }

    /// Sets the hook invoked after each successful broker.
    func setOnBrokered(_ handler: @escaping @Sendable () async -> Void) {
        onBrokered = handler
    }

    /// (Re)establishes the XPC link: connects, exports the core service, and
    /// attaches the extension. Tears down any existing connection first, so it
    /// is safe to call repeatedly. Does not touch domain suspend/resume — that
    /// is the supervisor's decision, taken in `onBrokered`.
    func broker() async throws {
        await teardown()

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
        await onBrokered?()
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

    /// Suspends the domain with a user-facing reason. Best-effort: failures are
    /// logged, not thrown, since suspend runs on error/shutdown paths.
    func suspend(reason: String) async {
        do {
            try await suspendDomain(reason)
            logger.info("Suspended sync: \(domain.id)")
        } catch {
            logger.error("Failed to suspend \(domain.id): \(error)")
        }
    }

    /// Resumes the domain. A safe no-op when the domain is already connected.
    /// Best-effort: failures are logged, not thrown.
    func resume() async {
        do {
            try await resumeDomain()
            logger.info("Resumed sync: \(domain.id)")
        } catch {
            logger.error("Failed to resume \(domain.id): \(error)")
        }
    }
}
