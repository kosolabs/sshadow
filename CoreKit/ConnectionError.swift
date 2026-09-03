import Common
import Foundation
import SwiftLibSSH

public enum ConnectionError: Message, Error {
    case unknownHost
    case connectionRefused
    case connectionTimedOut
    case invalidPrivateKey
    case authenticationFailed
    case remotePathNotFound
    case remotePathNotDirectory
    case unknown(domain: String, code: Int, message: String)

    public init(from error: any Error) {
        if let connectionError = error as? ConnectionError {
            self = connectionError
            return
        }
        if let sshError = error as? SSHError {
            switch sshError {
            case .connectionFailed(let message)
            where message.contains("Failed to resolve hostname"):
                self = .unknownHost
                return
            case .connectionFailed(let message)
            where message.contains("Connection refused")
                || message.contains("Socket error")
                || message.contains("Bad file descriptor"):
                self = .connectionRefused
                return
            case .connectionFailed(let message)
            where message.contains("Timeout"):
                self = .connectionTimedOut
                return
            case .authenticationFailed(let message)
            where message.contains("Failed to import private key"):
                self = .invalidPrivateKey
                return
            case .authenticationFailed:
                self = .authenticationFailed
                return
            case .sftpError(.noSuchFile, _):
                self = .remotePathNotFound
                return
            default:
                break
            }
        }
        let nsError = error as NSError
        self = .unknown(
            domain: nsError.domain,
            code: nsError.code,
            message: nsError.localizedDescription
        )
    }

    public var message: String {
        switch self {
        case .unknownHost: "Unknown host"
        case .connectionRefused: "Connection refused"
        case .connectionTimedOut: "Connection timed out"
        case .invalidPrivateKey: "Invalid private key"
        case .authenticationFailed: "Authentication failed"
        case .remotePathNotFound: "Remote path does not exist"
        case .remotePathNotDirectory: "Remote path is not a directory"
        case .unknown(_, _, let message): "Other: \(message)"
        }
    }
}
