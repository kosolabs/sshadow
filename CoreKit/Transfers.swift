import Foundation

@MainActor
@Observable
public final class Transfers {
    nonisolated public static let shared: Transfers = Transfers()

    private var transfers: [Transfer] = []

    nonisolated public init() {}
    
    public var value: [Transfer] {
        transfers
    }

    public var isEmpty: Bool {
        transfers.isEmpty
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
