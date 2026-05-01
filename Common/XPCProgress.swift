import Foundation

private let logger = Logger(category: "XPCProgress")

private enum XPCProgressUpdate: Codable {
    case totalUnitCount(Int64)
    case completedUnitCount(Int64)
}

public final class XPCProgressPublisher {
    public let progress: Progress
    private let session: XPCSession
    private let observers: [NSKeyValueObservation]

    public init(progress: Progress = Progress(), endpoint: XPCEndpoint) throws {
        let session = try XPCSession(endpoint: endpoint) { _ in
            progress.cancel()
        }

        var observers: [NSKeyValueObservation] = []
        observers.append(
            progress.observe(\.totalUnitCount) { p, _ in
                try? session.send(
                    XPCProgressUpdate.totalUnitCount(p.totalUnitCount)
                )
            }
        )
        observers.append(
            progress.observe(\.completedUnitCount) { p, _ in
                try? session.send(
                    XPCProgressUpdate.completedUnitCount(p.completedUnitCount)
                )
            }
        )

        self.progress = progress
        self.session = session
        self.observers = observers
    }

    deinit {
        for observer in observers {
            observer.invalidate()
        }
        session.cancel(reason: "Complete")
    }
}

public final class XPCProgressSubscriber {
    private let listener: XPCListener

    public init(progress: Progress) {
        let listener = XPCListener(targetQueue: nil) { request in
            request.accept { message in
                if let update = try? message.decode(as: XPCProgressUpdate.self)
                {
                    switch update {
                    case .totalUnitCount(let totalUnitCount):
                        progress.totalUnitCount = totalUnitCount
                    case .completedUnitCount(let completedUnitCount):
                        progress.completedUnitCount = completedUnitCount
                    }
                }
                return nil
            }
        }

        progress.cancellationHandler = {
            listener.cancel()
        }

        self.listener = listener
    }

    public var endpoint: XPCEndpoint {
        self.listener.endpoint
    }
}
