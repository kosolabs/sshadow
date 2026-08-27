import Foundation

private let logger = Logger(category: "XPCProgress")

@objc private protocol XPCProgressProtocol {
    func setTotalUnitCount(_ count: Int64)
    func setCompletedUnitCount(_ count: Int64)
    func setFinalCounts(
        total: Int64,
        completed: Int64,
        confirmed: @escaping () -> Void
    )
}

public final class XPCProgressPublisher {
    public let progress: Progress
    private let connection: NSXPCConnection
    private let observers: [NSKeyValueObservation]

    public init(
        progress: Progress = Progress(),
        endpoint: NSXPCListenerEndpoint
    ) {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(
            with: XPCProgressProtocol.self
        )
        connection.invalidationHandler = { progress.cancel() }
        connection.interruptionHandler = {
            logger.info("Progress XPC interrupted")
            progress.cancel()
        }
        connection.resume()

        let proxy = proxy(for: connection, operation: "update")

        var observers: [NSKeyValueObservation] = []
        observers.append(
            progress.observe(\.totalUnitCount) { p, _ in
                proxy.setTotalUnitCount(p.totalUnitCount)
            }
        )
        observers.append(
            progress.observe(\.completedUnitCount) { p, _ in
                proxy.setCompletedUnitCount(p.completedUnitCount)
            }
        )

        self.progress = progress
        self.connection = connection
        self.observers = observers
    }

    deinit {
        for observer in observers {
            observer.invalidate()
        }
        connection.invalidate()
    }

    public func confirmDelivery() async {
        await withCheckedContinuation { continuation in
            let proxy = proxy(
                for: connection,
                operation: "delivery confirmation",
                onError: { _ in continuation.resume() }
            )

            proxy.setFinalCounts(
                total: progress.totalUnitCount,
                completed: progress.completedUnitCount,
                confirmed: { continuation.resume() }
            )
        }
    }
}

private func proxy(
    for connection: NSXPCConnection,
    operation: String,
    onError handler: @escaping @Sendable (any Error) -> Void = { _ in }
) -> XPCProgressProtocol {
    if let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        logger.error("Progress \(operation) failed: \(error)")
        handler(error)
    }) as? XPCProgressProtocol {
        return proxy
    }
    logger.fatal("Progress proxy has unexpected type")
}

public final class XPCProgressSubscriber: NSObject, NSXPCListenerDelegate,
    XPCProgressProtocol
{
    private let progress: Progress
    private let listener: NSXPCListener

    public init(progress: Progress) {
        self.progress = progress
        self.listener = NSXPCListener.anonymous()
        super.init()

        progress.cancellationHandler = {
            logger.info("Progress cancelled; tearing down listener")
            self.listener.invalidate()
        }

        listener.delegate = self
        listener.resume()
    }

    deinit {
        listener.invalidate()
    }

    public var endpoint: NSXPCListenerEndpoint {
        listener.endpoint
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(
            with: XPCProgressProtocol.self
        )
        connection.exportedObject = self
        connection.resume()
        return true
    }

    public func setTotalUnitCount(_ count: Int64) {
        progress.totalUnitCount = count
    }

    public func setCompletedUnitCount(_ count: Int64) {
        progress.completedUnitCount = count
    }

    public func setFinalCounts(
        total: Int64,
        completed: Int64,
        confirmed: @escaping () -> Void
    ) {
        progress.totalUnitCount = total
        progress.completedUnitCount = completed
        confirmed()
    }
}
