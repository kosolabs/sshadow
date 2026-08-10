import Common
import Foundation
import SwiftData
import SwiftLibSSH

typealias SessionProvider =
    @Sendable (ConnectionConfig, @escaping ConnectionLostHandler) async throws
    -> Session

typealias EnumeratorSignal =
    @Sendable (ConnectionConfig) async throws -> Void

extension Session {
    static func provider(
        domainDbConfig: ModelConfiguration,
        sharedUrl: URL,
        signalEnumerator: @escaping EnumeratorSignal,
        transfers: Transfers
    ) -> SessionProvider {
        { config, handler in
            let ssh = try await SSHClient.connect(config: config)
            let sftp = try await ssh.sftp()
            let db = try await DomainDB.open(config: domainDbConfig)
            return Session(
                config: config,
                ssh: ssh,
                sftp: sftp,
                db: db,
                sharedUrl: sharedUrl,
                changesDetectedHandler: { try await signalEnumerator(config) },
                connectionLostHandler: handler,
                transfers: transfers
            )
        }
    }
}
