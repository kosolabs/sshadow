import Common
import CoreKit
import Foundation

@MainActor
@Observable
final class ConnectionCoordinator {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var errors: [UUID: Error] = [:]
    private var paused: Set<UUID> = Set()

    var isAnyBusy: Bool {
        !tasks.isEmpty
    }

    var isAnyError: Bool {
        !errors.isEmpty
    }

    func isBusy(_ profile: ConnectionConfigModel) -> Bool {
        tasks[profile.id] != nil
    }

    func error(_ profile: ConnectionConfigModel) -> Error? {
        errors[profile.id]
    }

    func setEnabled(_ enabled: Bool, on profile: ConnectionConfigModel) {
        let id = profile.id
        tasks[id]?.cancel()
        errors[id] = nil

        tasks[id] = Task { @MainActor in
            do {
                try await enabled ? profile.enable() : profile.disable()
            } catch {
                if !Task.isCancelled {
                    errors[id] = error
                }
            }
            tasks[id] = nil
        }
    }

    func isPaused(_ profile: ConnectionConfigModel) -> Bool {
        return paused.contains(profile.id)
    }

    func pause(_ profile: ConnectionConfigModel) {
        tasks[profile.id]?.cancel()
        errors[profile.id] = nil

        tasks[profile.id] = Task { @MainActor in
            do {
                try await profile.pause()
                paused.insert(profile.id)
            } catch is CancellationError {
            } catch {
                errors[profile.id] = error
            }
            tasks[profile.id] = nil
        }
    }
    
    func reconnect(_ profile: ConnectionConfigModel) {
        let id = profile.id
        tasks[id]?.cancel()
        errors[id] = nil

        tasks[id] = Task { @MainActor in
            do {
                try await profile.reconfigure()
                paused.remove(profile.id)
            } catch is CancellationError {
            } catch {
                errors[profile.id] = error
            }
            tasks[profile.id] = nil
        }
    }
}
