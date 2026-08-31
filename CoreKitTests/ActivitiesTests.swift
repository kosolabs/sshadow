import Foundation
import Testing

@testable import CoreKit

@MainActor
struct ActivitiesTests {
    @Test func inactiveWhenNoEventsOrTransfers() {
        let activities = Activities()
        #expect(!activities.isActive)
    }

    @Test func activeWhenATransferIsInProgress() {
        let activities = Activities()

        _ = activities.transfers.begin(name: "file", progress: Progress())

        #expect(activities.isActive)
    }

    @Test func activeWhenAnEventIsPending() async {
        let activities = Activities()

        activities.events.add(.upload(path: "/f"), outcome: .succeeded())

        await waitUntil { activities.isActive }
        #expect(activities.isActive)
    }
}
