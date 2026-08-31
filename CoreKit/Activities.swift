import Common
import Foundation

@MainActor
@Observable
public final class Activities {
    nonisolated public static let shared: Activities = Activities()

    nonisolated public let events: Events<ContinuousClock>
    nonisolated public let transfers: Transfers<ContinuousClock>

    nonisolated init(clock: ContinuousClock = ContinuousClock()) {
        self.events = Events(clock: clock)
        self.transfers = Transfers(clock: clock)
    }

    public var isActive: Bool {
        events.isActive || transfers.isActive
    }
}
