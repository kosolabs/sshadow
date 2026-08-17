import Common
import Foundation
import SwiftLibSSH

public enum OfflineReason: Equatable, Sendable {
    case disabled
    case paused
    case failed(ConnectionError)
}

public enum ConnectionStatus: Equatable, Sendable {
    case offline(OfflineReason)
    case connecting
    case reconnecting(ConnectionError?, nextAttempt: Date?)
    case online
}
