import CoreKit

extension ConnectionError {
    var message: String {
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

    var systemImage: String {
        switch self {
        case .invalidPrivateKey, .authenticationFailed:
            "lock.circle"
        case .unknownHost, .connectionRefused, .connectionTimedOut:
            "network.slash"
        case .remotePathNotFound, .remotePathNotDirectory:
            "questionmark.folder"
        case .unknown:
            "bolt.slash"
        }
    }
}
