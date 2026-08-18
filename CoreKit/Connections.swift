import Common
import Foundation

@MainActor
@Observable
public final class Connections {
    nonisolated public static let shared: Connections = Connections()

    private var statuses: [UUID: ConnectionStatus] = [:]

    nonisolated public init() {}

    public func status(for id: UUID) -> ConnectionStatus {
        self.statuses[id] ?? .offline(.disabled)
    }

    nonisolated func update(_ status: ConnectionStatus, for id: UUID) {
        Task { @MainActor in
            self.statuses[id] = status
        }
    }

    public func isBusy(id: UUID) -> Bool {
        if case .connecting = status(for: id) { true } else { false }
    }

    public func isOffline(id: UUID) -> Bool {
        if case .offline = status(for: id) { true } else { false }
    }
}
