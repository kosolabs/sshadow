import Common
import Foundation
import SwiftLibSSH

public enum OfflineReason: Equatable, Sendable {
    case disabled
    case paused
    case failed(ConnectionError)
    
    public var text: String {
        switch self {
        case .disabled:
            "The connection is disconnecting."
        case .paused:
            "The connection is paused. Reconnect it in Settings."
        case .failed:
            "The server is unreachable. Check your network connection."
        }
    }
}

public enum ConnectionStatus: Equatable, Sendable {
    case offline(OfflineReason)
    case disconnecting(OfflineReason)
    case connecting
    case reconnecting(ConnectionError?, nextAttempt: Date?)
    case online
}
