import Foundation

@MainActor
@Observable
public final class Activities {
    nonisolated public static let shared: Activities = Activities()

    public private(set) var transfers: [Transfer] = []

    nonisolated public init() {}
    
    public var isBusy: Bool {
        !transfers.isEmpty
    }

    public func begin(name: String, progress: Progress) -> Transfer {
        let transfer = Transfer(
            name: name,
            progress: progress
        )
        transfers.append(transfer)
        return transfer
    }

    nonisolated public func end(transfer: Transfer) {
        Task { @MainActor in
            self.transfers.removeAll { $0 === transfer }
        }
    }
}
