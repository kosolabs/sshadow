import Foundation
import SwiftLibSSH

enum ConnectionTestStatus: Equatable {
    case notStarted
    case testing
    case success
    case invalidConfig(String)
    case unknownHost
    case connectionRefused
    case timeout
    case userauthPasswordFailed
    case pathNotADirectory
    case pathNotFound
    case other(String)
}

protocol ConnectionTester {
    func test(config: ConnectionConfigSnapshot) async -> ConnectionTestStatus
}

struct DefaultConnectionTester: ConnectionTester {
    func test(config: ConnectionConfigSnapshot) async -> ConnectionTestStatus {
        do {
            return try await withAuthenticatedClient(config: config) {
                sshClient in
                return try await sshClient.withSftp { sftpClient in
                    let attrs = try await sftpClient.attributes(
                        atPath: config.path
                    )
                    if attrs.type != .directory {
                        return .pathNotADirectory
                    }
                    return .success
                }

            }
        } catch {
            guard let sshError = error as? SSHError else {
                return .other("\(error)")
            }
            switch sshError {
            case .connectFailed(let message):
                let msg = message.lowercased()
                if msg.contains("failed to resolve hostname") { return .unknownHost }
                if msg.contains("connection refused") { return .connectionRefused }
                if msg.contains("timeout") { return .timeout }
                return .other(message)
            case .userauthPasswordFailed:
                return .userauthPasswordFailed
            case .sftpStatFailed(let message):
                if message.lowercased().contains("no such file") {
                    return .pathNotFound
                }
                return .other(message)
            default:
                return .other("\(sshError)")
            }
        }
    }
}

private func withAuthenticatedClient(
    config: ConnectionConfigSnapshot,
    perform: @Sendable (SSHClient) async throws -> ConnectionTestStatus
) async throws -> ConnectionTestStatus {
    switch config.authMethod {
    case .password:
        guard let password = config.password else {
            return .invalidConfig("Password is required")
        }

        return try await SSHClient.withAuthenticatedClient(
            host: config.host,
            port: config.port,
            user: config.user,
            password: password,
            perform: perform
        )
    case .privateKey:
        guard let privateKeyURL = config.privateKeyURL else {
            return .invalidConfig("Private key is required")
        }
        guard privateKeyURL.startAccessingSecurityScopedResource() else {
            return .invalidConfig("Failed to access private key file")
        }
        defer { privateKeyURL.stopAccessingSecurityScopedResource() }
        return try await SSHClient.withAuthenticatedClient(
            host: config.host,
            port: config.port,
            user: config.user,
            privateKeyURL: privateKeyURL,
            passphrase: config.privateKeyPassphrase,
            perform: perform
        )
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
