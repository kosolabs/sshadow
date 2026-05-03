import Foundation
import Testing

@testable import Common

struct XPCProgressTests {
    @Test func syncsTotalUnitCount() async throws {
        let sinkProgress = Progress()
        let sink = XPCProgressSubscriber(progress: sinkProgress)

        let sourceProgress = Progress()
        let source = XPCProgressPublisher(
            progress: sourceProgress,
            endpoint: sink.endpoint
        )

        sourceProgress.totalUnitCount = 100

        try await poll { sinkProgress.totalUnitCount == 100 }
        #expect(sinkProgress.totalUnitCount == 100)

        withExtendedLifetime((source, sink)) {}
    }

    @Test func syncsCompletedUnitCount() async throws {
        let sinkProgress = Progress()
        let sink = XPCProgressSubscriber(progress: sinkProgress)

        let sourceProgress = Progress()
        sourceProgress.totalUnitCount = 100
        let source = XPCProgressPublisher(
            progress: sourceProgress,
            endpoint: sink.endpoint
        )

        sourceProgress.completedUnitCount = 50

        try await poll { sinkProgress.completedUnitCount == 50 }
        #expect(sinkProgress.completedUnitCount == 50)

        withExtendedLifetime((source, sink)) {}
    }

    @Test func syncsMultipleUpdates() async throws {
        let sinkProgress = Progress()
        let sink = XPCProgressSubscriber(progress: sinkProgress)

        let sourceProgress = Progress()
        let source = XPCProgressPublisher(
            progress: sourceProgress,
            endpoint: sink.endpoint
        )

        sourceProgress.totalUnitCount = 200
        sourceProgress.completedUnitCount = 50

        try await poll { sinkProgress.completedUnitCount == 50 }
        #expect(sinkProgress.totalUnitCount == 200)
        #expect(sinkProgress.completedUnitCount == 50)

        sourceProgress.completedUnitCount = 200

        try await poll { sinkProgress.completedUnitCount == 200 }
        #expect(sinkProgress.completedUnitCount == 200)

        withExtendedLifetime((source, sink)) {}
    }

    @Test func sinkCancellationCancelsSourceProgress() async throws {
        let sinkProgress = Progress()
        let sink = XPCProgressSubscriber(progress: sinkProgress)

        let sourceProgress = Progress()
        let source = XPCProgressPublisher(
            progress: sourceProgress,
            endpoint: sink.endpoint
        )

        // Allow the XPC connection to establish
        sourceProgress.totalUnitCount = 1
        try await poll { sinkProgress.totalUnitCount == 1 }

        sinkProgress.cancel()

        try await poll { sourceProgress.isCancelled }
        #expect(sourceProgress.isCancelled)

        withExtendedLifetime((source, sink)) {}
    }
}

private func poll(
    timeout: Duration = .seconds(2),
    condition: @escaping () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            #expect(Bool(false), "Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
