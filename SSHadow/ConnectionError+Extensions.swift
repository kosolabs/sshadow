import CoreKit

extension ConnectionError {
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
