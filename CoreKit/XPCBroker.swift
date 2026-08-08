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
    private var service: CoreService?

    init(domain: NSFileProviderDomain) {
        self.domain = domain
    }

    func broker(exporting service: CoreService) async {
        self.service = service
        await broker()
    }

    private func broker() async {
        guard connection == nil else { return }

        let connection = await awaitConnection()
        connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
        connection.invalidationHandler = { [weak self] in
            Task {
                guard let self else { return }
                await self.rebrokerXpc()
            }
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.attach()
        self.connection = connection

        logger.info("XPC brokered: \(domain)")
    }

    private func awaitConnection() async -> NSXPCConnection {
        while true {
            do {
                return try await domain.service.fileProviderConnection()
            } catch {
                logger.error("Failed to broker XPC for \(domain): \(error)")
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func rebrokerXpc() async {
        logger.info("XPC invalidated: \(domain)")
        connection = nil
        await broker()
    }

    func teardown() async {
        guard let connection else { return }
        self.connection = nil

        let ext = connection.remoteObjectProxy as! ExtXPC
        await ext.detach()
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()

        logger.info("XPC torn down: \(domain)")
    }
}
