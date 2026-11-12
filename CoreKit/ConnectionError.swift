import Common
import Foundation
import SwiftRussh

public enum ConnectionError: Message, Error {
    case unknownHost
    case connectionRefused
    case connectionTimedOut
    case hostUnreachable
    case connectionLost
    case invalidPrivateKey
    case authenticationFailed
    case hostKeyChanged(SSHHostKey)
    case remotePathNotFound
    case remotePathNotDirectory
    case cancelled
    case unknown(domain: String, code: Int, message: String)

    public init(from error: any Error) {
        if let connectionError = error as? ConnectionError {
            self = connectionError
            return
        }
        if let sshError = error as? SSHError {
            switch sshError {
            case .connectionFailed(.unknownHost, _):
                self = .unknownHost
                return
            case .connectionFailed(.refused, _):
                self = .connectionRefused
                return
            case .connectionFailed(.timedOut, _):
                self = .connectionTimedOut
                return
            case .connectionFailed(.unreachable, _):
                self = .hostUnreachable
                return
            case .connectionFailed(.lost, _):
                self = .connectionLost
                return
            case .privateKey:
                self = .invalidPrivateKey
                return
            case .authenticationFailed:
                self = .authenticationFailed
                return
            case .hostKeyMismatch(_, let actual, _):
                self = .hostKeyChanged(actual)
                return
            case .sftp(.noSuchFile, _):
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

    public var isRetryable: Bool {
        switch self {
        case .unknownHost, .connectionRefused, .connectionTimedOut,
            .hostUnreachable, .connectionLost, .cancelled, .unknown:
            true
        case .invalidPrivateKey, .authenticationFailed, .hostKeyChanged,
            .remotePathNotFound, .remotePathNotDirectory:
            false
        }
    }

    public var detail: String {
        switch self {
        case .hostKeyChanged(let hostKey):
            "Host key changed; the server now presents \(hostKey.fingerprint)"
        default:
            message
        }
    }

    public var message: String {
        switch self {
        case .unknownHost: "Unknown host"
        case .connectionRefused: "Connection refused"
        case .connectionTimedOut: "Connection timed out"
        case .hostUnreachable: "Host unreachable"
        case .connectionLost: "Connection lost"
        case .invalidPrivateKey: "Invalid private key"
        case .authenticationFailed: "Authentication failed"
        case .hostKeyChanged: "Host key changed"
        case .remotePathNotFound: "Remote path does not exist"
        case .remotePathNotDirectory: "Remote path is not a directory"
        case .cancelled: "Cancelled"
        case .unknown(_, _, let message): "Other: \(message)"
        }
    }
}
