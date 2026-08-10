import Common
import Foundation
import SwiftData
import SwiftLibSSH

typealias SessionProvider = @Sendable (ConnectionConfig) async throws -> Session

extension Session {
    static func provider(
        domainDbConfig: ModelConfiguration,
        sharedUrl: URL,
        signal: @escaping SignalEnumerator,
        transfers: Transfers
    ) -> SessionProvider {
        { config in
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
    }
}
