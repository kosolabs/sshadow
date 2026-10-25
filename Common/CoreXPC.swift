import Foundation

@objc public protocol ExtXPC {
    func attach(reply: @escaping @Sendable () -> Void)
    func detach(reply: @escaping @Sendable () -> Void)
}

@objc public protocol CoreXPC {
    func handle(
        _ data: Data,
        reply: @escaping @Sendable (Data?, (any Error)?) -> Void
    )
    func handle(
        _ data: Data,
        progressEndpoint: NSXPCListenerEndpoint,
        reply: @escaping @Sendable (Data?, (any Error)?) -> Void
    )
}

extension NSXPCConnection {
    public func attach() async throws {
        try await call { (ext: ExtXPC, reply) in
            ext.attach { reply(.success(())) }
        }
    }

    public func detach() async throws {
        try await call { (ext: ExtXPC, reply) in
            ext.detach { reply(.success(())) }
        }
    }

    public func handle(_ data: Data) async throws -> Data {
        try await call { (core: CoreXPC, reply) in
            core.handle(data) { reply(Result($0, $1)) }
        }
    }

    public func handle(
        _ data: Data,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws -> Data {
        try await call { (core: CoreXPC, reply) in
            core.handle(data, progressEndpoint: progressEndpoint) {
                reply(Result($0, $1))
            }
        }
    }
}

extension Result where Failure == any Error {
    fileprivate init(_ value: Success?, _ error: (any Error)?) {
        if let value {
            self = .success(value)
        } else {
            self = .failure(error ?? CoreError.serviceUnreachable)
        }
    }
}
