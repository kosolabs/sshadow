import Common
import Foundation
import SwiftLibSSH

public enum OfflineReason: Equatable, Sendable {
    case disabled
    case paused
    case failed(ConnectionError)
    case wrongExtension(URL)
    
    public var text: String {
        switch self {
        case .disabled:
            "The connection is disconnecting."
        case .paused:
            "The connection is paused. Resume it from the SSHadow menu."
        case .failed:
            "The server is unreachable. Check your network connection."
        case .wrongExtension:
            "Another copy of SSHadow is interfering. Open SSHadow to fix it."
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
