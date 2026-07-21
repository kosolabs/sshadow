import Foundation

private let logger = Logger(category: "XPCProgress")

@objc private protocol XPCProgressProtocol {
    func setTotalUnitCount(_ count: Int64)
    func setCompletedUnitCount(_ count: Int64)
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
        connection.interruptionHandler = { progress.cancel() }
        connection.resume()

        let sink = connection.remoteObjectProxy as? XPCProgressProtocol

        var observers: [NSKeyValueObservation] = []
        observers.append(
            progress.observe(\.totalUnitCount) { p, _ in
                sink?.setTotalUnitCount(p.totalUnitCount)
            }
        )
        observers.append(
            progress.observe(\.completedUnitCount) { p, _ in
                sink?.setCompletedUnitCount(p.completedUnitCount)
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
}
