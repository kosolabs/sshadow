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
    func test(
        host: String,
        port: UInt16,
        user: String,
        password: String,
        path: String
    ) async -> ConnectionTestStatus

    func test(
        host: String,
        port: UInt16,
        user: String,
        privateKeyURL: URL,
        passphrase: String?,
        path: String
    ) async -> ConnectionTestStatus
}

struct DefaultConnectionTester: ConnectionTester {
    func test(
        host: String,
        port: UInt16,
        user: String,
        password: String,
        path: String
    ) async -> ConnectionTestStatus {
        do {
            return try await SSHClient.withAuthenticatedClient(
                host: host,
                port: port,
                user: user,
                password: password
            ) { sshClient in
                try await sshClient.withSftp { sftpClient in
                    let attrs = try await sftpClient.attributes(atPath: path)
                    if attrs.type != .directory {
                        return .pathNotADirectory
                    }
                    return .success
                }
            }
        } catch {
            print("connection test failed: \(error)")

            if let sshError = error as? SSHError {
                switch sshError {
                case .connectFailed(let message):
                    if message.contains("Failed to resolve hostname") {
                        return .unknownHost
                    }
                    if message.contains("Connection refused") {
                        return .connectionRefused
                    }
                    if message.contains("Timeout") {
                        return .timeout
                    }
                case .userauthPasswordFailed:
                    return .userauthPasswordFailed
                case .sftpStatFailed(let message):
                    if message.contains("No such file") {
                        return .pathNotFound
                    }
                default:
                    break
                }
            }

            return .other("\(error)")
        }
    }

    func test(
        host: String,
        port: UInt16,
        user: String,
        privateKeyURL: URL,
        passphrase: String? = nil,
        path: String
    ) async -> ConnectionTestStatus {
        do {
            guard privateKeyURL.startAccessingSecurityScopedResource() else {
                return .other("failed to startAccessingSecurityScopedResource")
            }
            defer { privateKeyURL.stopAccessingSecurityScopedResource() }
            return try await SSHClient.withAuthenticatedClient(
                host: host,
                port: port,
                user: user,
                privateKeyURL: privateKeyURL,
                passphrase: passphrase
            ) { sshClient in
                try await sshClient.withSftp { sftpClient in
                    let attrs = try await sftpClient.attributes(atPath: path)
                    if attrs.type != .directory {
                        return .pathNotADirectory
                    }
                    return .success
                }
            }
        } catch {
            print("connection test failed: \(error)")

            if let sshError = error as? SSHError {
                switch sshError {
                case .connectFailed(let message):
                    if message.contains("Failed to resolve hostname") {
                        return .unknownHost
                    }
                    if message.contains("Connection refused") {
                        return .connectionRefused
                    }
                    if message.contains("Timeout") {
                        return .timeout
                    }
                case .userauthPasswordFailed:
                    return .userauthPasswordFailed
                case .sftpStatFailed(let message):
                    if message.contains("No such file") {
                        return .pathNotFound
                    }
                default:
                    break
                }
            }

            return .other("\(error)")
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
