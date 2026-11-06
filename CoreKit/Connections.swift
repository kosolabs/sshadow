import Common
import Foundation

@MainActor
@Observable
public final class Connections {
    nonisolated public static let shared: Connections = Connections()

    private var statuses: [UUID: ConnectionStatus] = [:]
    private var hostKeyChecks: [UUID: ConnectionStatus] = [:]

    nonisolated public init() {}

    public func status(for id: UUID) -> ConnectionStatus {
        hostKeyChecks[id] ?? statuses[id] ?? .offline(.disabled)
    }

    func beginHostKeyCheck(id: UUID) {
        hostKeyChecks[id] = .connecting
    }

    func failHostKeyCheck(id: UUID, error: ConnectionError) {
        hostKeyChecks[id] = .offline(.failed(error))
    }

    func endHostKeyCheck(id: UUID) {
        hostKeyChecks[id] = nil
    }

    nonisolated func update(_ status: ConnectionStatus, for id: UUID) {
        Task { @MainActor in
            self.statuses[id] = status
        }
    }

    public func isBusy(id: UUID) -> Bool {
        switch status(for: id) {
        case .connecting, .disconnecting:
            return true
        default:
            return false
        }
    }

    public func isOffline(id: UUID) -> Bool {
        if case .offline = status(for: id) { true } else { false }
    }
}
