import Foundation
import SwiftLibSSH

private let logger = Logger(category: "ConnectionTester")

public enum ConnectionTestError: Error, Equatable {
    case unknownHost
    case connectionRefused
    case timeout
    case userauthPasswordFailed
    case invalidPrivateKey
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
            try await SSHClient.withSession(config: config) { _, sftp in
                logger.debug("SFTP Limits for \(config.socket): \(sftp.limits)")
                let attrs = try await sftp.attributes(
                    at: config.path == "" ? "." : config.path
                )
                if attrs.type != .directory {
                    throw ConnectionTestError.pathNotADirectory
                }
            }
        } catch SSHError.connectionFailed(let message)
            where message.contains("Failed to resolve hostname")
        {
            logger.info("Unknown host: \(message)")
            throw ConnectionTestError.unknownHost
        } catch SSHError.connectionFailed(let message)
            where message.contains("Connection refused")
            || message.contains("Socket error")
            || message.contains("Bad file descriptor")
        {
            logger.info("Connection refused: \(message)")
            throw ConnectionTestError.connectionRefused
        } catch SSHError.connectionFailed(let message)
            where message.contains("Timeout")
        {
            logger.info("Connection timeout: \(message)")
            throw ConnectionTestError.timeout
        } catch SSHError.authenticationFailed(let message)
            where message.contains("Failed to import private key")
        {
            logger.info("Invalid private key")
            throw ConnectionTestError.invalidPrivateKey
        } catch SSHError.authenticationFailed(let message) {
            logger.info("Authentication failed: \(message)")
            throw ConnectionTestError.userauthPasswordFailed
        } catch SSHError.sftpError(.noSuchFile, let path) {
            logger.info("No such file: \(path)")
            throw ConnectionTestError.pathNotFound
        } catch {
            logger.error("Unhandled error: \(error)")
            throw error
        }
    }
}
