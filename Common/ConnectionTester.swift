import Foundation
import SwiftLibSSH

private let logger = Logger(category: "ConnectionTester")

public enum ConnectionTestError: Error, Equatable {
    case unknownHost
    case connectionRefused
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
            try await SSHClient.withSession(config: config) {
                _,
                sftpClient in
                let attrs = try await sftpClient.attributes(
                    atPath: config.path
                )
                if attrs.type != .directory {
                    throw ConnectionTestError.pathNotADirectory
                }
            }
        } catch {
            logger.error("Error while testing connection: \(error)")
            guard let sshError = error as? SSHError else {
                throw error
            }

            switch sshError {
            case .connectionFailed(let message):
                if message.contains("Failed to resolve hostname") {
                    throw ConnectionTestError.unknownHost
                }
                if message.contains("Connection refused")
                    || message.contains("Socket error")
                    || message.contains("Bad file descriptor")
                {
                    throw ConnectionTestError.connectionRefused
                }
                if message.contains("Timeout") {
                    throw ConnectionTestError.timeout
                }
            case .authenticationFailed:
                throw ConnectionTestError.userauthPasswordFailed
            case .sftpError(let sftpError, _):
                switch sftpError {
                case .noSuchFile:
                    throw ConnectionTestError.pathNotFound
                default:
                    throw error
                }
            default:
                throw error
            }
            throw error
        }
    }
}
