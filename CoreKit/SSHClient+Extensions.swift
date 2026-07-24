import Common
import Foundation
import SwiftLibSSH

private let logger = Logger(category: "SSHClient")

extension SSHClient {
    public enum TestError: Message, Error {
        case unknownHost
        case connectionRefused
        case connectionTimedOut
        case invalidPrivateKey
        case passwordAuthFailed
        case remotePathNotFound
        case remotePathNotDirectory
        case unknown(domain: String, code: Int, message: String)

        public init(from error: any Error) {
            if let testError = error as? TestError {
                self = testError
                return
            }
            logger.error("Unhandled error type: \(error)")
            let nsError = error as NSError
            self = .unknown(
                domain: nsError.domain,
                code: nsError.code,
                message: nsError.localizedDescription
            )
        }
    }

    public static func test(config: ConnectionConfig) async throws(TestError) {
        do {
            try await SSHClient.withSession(config: config) { _, sftp in
                let attrs = try await sftp.attributes(at: config.path())
                if attrs.type != .directory {
                    throw TestError.remotePathNotDirectory
                }
            }
        } catch SSHError.connectionFailed(let message)
            where message.contains("Failed to resolve hostname")
        {
            throw .unknownHost
        } catch SSHError.connectionFailed(let message)
            where message.contains("Connection refused")
            || message.contains("Socket error")
            || message.contains("Bad file descriptor")
        {
            throw .connectionRefused
        } catch SSHError.connectionFailed(let message)
            where message.contains("Timeout")
        {
            throw .connectionTimedOut
        } catch SSHError.authenticationFailed(let message)
            where message.contains("Failed to import private key")
        {
            throw .invalidPrivateKey
        } catch SSHError.authenticationFailed {
            throw .passwordAuthFailed
        } catch SSHError.sftpError(.noSuchFile, _) {
            throw .remotePathNotFound
        } catch {
            throw TestError(from: error)
        }
    }

    public static func connect(
        config: ConnectionConfig
    ) async throws -> SSHClient {
        switch config.authMethod {
        case .none:
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user
            )
        case .password(let password):
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                auth: .password(password)
            )
        case .privateKey(let base64PrivateKey, let passphrase):
            return try await SSHClient.connect(
                host: config.host,
                port: config.port,
                user: config.user,
                auth: .privateKeyData(
                    base64: base64PrivateKey,
                    passphrase: passphrase
                )
            )
        }
    }

    @discardableResult
    public static func withSession<T: Sendable>(
        config: ConnectionConfig,
        perform: @Sendable (SSHClient, SFTPClient) async throws -> T
    ) async throws -> T {
        let sshClient = try await connect(config: config)
        do {
            let result = try await sshClient.withSftp { sftpClient in
                try await perform(sshClient, sftpClient)
            }
            await sshClient.close()
            return result
        } catch {
            await sshClient.close()
            throw error
        }
    }
}
