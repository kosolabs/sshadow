import Foundation
import OSLog
import SSHadowShared
internal import SwiftLibSSH

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "ConnectionTester"
)

public enum ConnectionTestError: Error, Equatable {
    case invalidConfig(String)
    case unknownHost
    case connectionRefused
    case socketError
    case timeout
    case userauthPasswordFailed
    case pathNotADirectory
    case pathNotFound
}

public protocol ConnectionTester {
    func test(config: ConnectionConfig) async throws
}

public struct DefaultConnectionTester: ConnectionTester {
    public init() {}

    public func test(config: ConnectionConfig) async throws {
        try await withAuthenticatedClient(config: config) {
            sshClient in
            try await sshClient.withSftp { sftpClient in
                let attrs = try await sftpClient.attributes(
                    atPath: config.path
                )
                if attrs.type != .directory {
                    throw ConnectionTestError.pathNotADirectory
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
            throw ConnectionTestError.unknownHost
        }
        if message.contains("Connection refused") {
            throw ConnectionTestError.connectionRefused
        }
        if message.contains("Socket error") {
            throw ConnectionTestError.socketError
        }
        if message.contains("Timeout") {
            throw ConnectionTestError.timeout
        }
    case .userauthPasswordFailed:
        throw ConnectionTestError.userauthPasswordFailed
    case .sftpStatFailed(let message):
        if message.contains("No such file") {
            throw ConnectionTestError.pathNotFound
        }
    default:
        throw error
    }
    throw error
}

private func withAuthenticatedClient(
    config: ConnectionConfig,
    perform: @Sendable (SSHClient) async throws -> Void
) async throws {
    switch config.authMethod {
    case .password:
        guard let password = config.password else {
            throw ConnectionTestError.invalidConfig("Password is required")
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
            throw ConnectionTestError.invalidConfig("Private key is required")
        }
        guard privateKeyURL.startAccessingSecurityScopedResource() else {
            throw ConnectionTestError.invalidConfig(
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
    @unknown default:
        fatalError("Unknown authentication method")
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
