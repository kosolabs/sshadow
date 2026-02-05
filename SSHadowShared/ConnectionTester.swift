import Foundation
import OSLog
import SwiftLibSSH

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "ConnectionTester"
)

public enum ConnectionTestError: Error, Equatable {
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
        do {
            try await SSHClient.withAuthenticatedClient(config: config) {
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
        } catch {
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
    }
}

extension Data {
    public func decoded(as encoding: String.Encoding) throws -> String {
        guard let str = String(data: self, encoding: encoding) else {
            throw SSHClientError.decodeFailed(
                "Failed to decode data as \(encoding)"
            )
        }
        return str
    }
}
