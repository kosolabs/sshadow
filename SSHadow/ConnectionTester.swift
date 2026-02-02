import Foundation
import OSLog
import SwiftLibSSH

enum ConnectionTestStatus: Error, Equatable {
    case invalidConfig(String)
    case unknownHost
    case connectionRefused
    case socketError
    case timeout
    case userauthPasswordFailed
    case pathNotADirectory
    case pathNotFound
}

protocol ConnectionTester {
    func test(config: ConnectionConfigSnapshot) async throws
}

struct DefaultConnectionTester: ConnectionTester {
    func test(config: ConnectionConfigSnapshot) async throws {
        try await withAuthenticatedClient(config: config) {
            sshClient in
            try await sshClient.withSftp { sftpClient in
                let attrs = try await sftpClient.attributes(
                    atPath: config.path
                )
                if attrs.type != .directory {
                    throw ConnectionTestStatus.pathNotADirectory
                }
            }

        }
    }
}

private func mapError(error: Error) throws {
    logger.notice("Error while testing connection: \(error)")
    guard let sshError = error as? SSHError else {
        throw error
    }

    switch sshError {
    case .connectFailed(let message):
        if message.contains("Failed to resolve hostname") {
            throw ConnectionTestStatus.unknownHost
        }
        if message.contains("Connection refused") {
            throw ConnectionTestStatus.connectionRefused
        }
        if message.contains("Socket error") {
            throw ConnectionTestStatus.socketError
        }
        if message.contains("Timeout") {
            throw ConnectionTestStatus.timeout
        }
    case .userauthPasswordFailed:
        throw ConnectionTestStatus.userauthPasswordFailed
    case .sftpStatFailed(let message):
        if message.contains("No such file") {
            throw ConnectionTestStatus.pathNotFound
        }
    default:
        throw error
    }
    throw error
}

private func withAuthenticatedClient(
    config: ConnectionConfigSnapshot,
    perform: @Sendable (SSHClient) async throws -> Void
) async throws {
    switch config.authMethod {
    case .password:
        guard let password = config.password else {
            throw ConnectionTestStatus.invalidConfig("Password is required")
        }
        do {
            try await SSHClient.withAuthenticatedClient(
                host: config.host,
                port: config.port,
                user: config.user,
                password: password,
                perform: perform
            )
        } catch {
            try mapError(error: error)
        }
    case .privateKey:
        guard let privateKeyURL = config.privateKeyURL else {
            throw ConnectionTestStatus.invalidConfig("Private key is required")
        }
        guard privateKeyURL.startAccessingSecurityScopedResource() else {
            throw ConnectionTestStatus.invalidConfig(
                "Failed to access private key file"
            )
        }
        defer { privateKeyURL.stopAccessingSecurityScopedResource() }
        do {
            try await SSHClient.withAuthenticatedClient(
                host: config.host,
                port: config.port,
                user: config.user,
                privateKeyURL: privateKeyURL,
                passphrase: config.privateKeyPassphrase,
                perform: perform
            )
        } catch {
            try mapError(error: error)
        }
    }
}

extension Data {
    func decoded(as encoding: String.Encoding) throws -> String {
        guard let str = String(data: self, encoding: encoding) else {
            throw SSHClientError.decodeFailed(
                "Failed to decode data as \(encoding)"
            )
        }
        return str
    }
}
