import Common
import Foundation
import SwiftData
import SwiftLibSSH

private let logger = Logger(category: "SessionSupervisor")

/// Owns a single domain's live SSH `Session`: builds it (coalescing concurrent
/// callers onto one in-flight connect), runs the periodic poll loop, and tears
/// it down. The session's SSH connection is immutable, so recovery means
/// replacing the whole `Session` — which is why ownership lives here rather than
/// inside `Session` itself.
actor SessionSupervisor {
    private let config: ConnectionConfig
    private let domainDbConfig: ModelConfiguration
    private let sharedUrl: URL
    private let signal: SignalEnumerator
    private let transfers: Transfers
    private let pollInterval: Duration?

    private var session: Session?
    private var connectTask: Task<Session, any Error>?
    private var bgTask: Task<Void, Never>?

    init(
        config: ConnectionConfig,
        domainDbConfig: ModelConfiguration,
        sharedUrl: URL,
        signal: @escaping SignalEnumerator,
        transfers: Transfers,
        pollInterval: Duration?
    ) {
        self.config = config
        self.domainDbConfig = domainDbConfig
        self.sharedUrl = sharedUrl
        self.signal = signal
        self.transfers = transfers
        self.pollInterval = pollInterval
    }

    func connect() async throws -> Session {
        if let session {
            return session
        }

        if let connectTask {
            return try await connectTask.value
        }

        let task = Task {
            let ssh = try await SSHClient.connect(config: config)
            let sftp = try await ssh.sftp()
            let db = try await DomainDB.open(config: domainDbConfig)
            return Session(
                config: config,
                ssh: ssh,
                sftp: sftp,
                db: db,
                sharedUrl: sharedUrl,
                signal: signal,
                transfers: transfers
            )
        }
        connectTask = task

        do {
            let session = try await task.value
            self.session = session
            connectTask = nil
            start()
            return session
        } catch {
            connectTask = nil
            throw error
        }
    }

    func disconnect() async {
        connectTask?.cancel()
        connectTask = nil
        bgTask?.cancel()
        bgTask = nil
        if let session {
            await session.close()
            self.session = nil
        }
    }

    private func start() {
        guard bgTask == nil, let pollInterval else { return }
        bgTask = Task { [weak self] in
            await self?.run(interval: pollInterval)
        }
    }

    private func run(interval: Duration) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
                try await session?.poll()
            } catch is CancellationError {
                return
            } catch {
                logger.error("Periodic poll failed: \(error)")
            }
        }
    }
}
