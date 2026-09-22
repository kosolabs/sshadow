import Foundation
import Testing

@testable import ExtensionKit

/// Records the order in which steps run so tests can assert on sequencing.
private final class Recorder {
    var calls: [String] = []

    func record(_ name: String) {
        calls.append(name)
    }
}

private struct StepFailure: Error {}

struct ProgressStepsTests {
    @Test func executeWithNoStepsCompletes() async throws {
        let progress = Progress()

        try await progress.steps().execute()

        #expect(progress.isFinished)
        #expect(progress.fractionCompleted == 1.0)
    }

    @Test func executeRunsStepsInOrder() async throws {
        let recorder = Recorder()
        let progress = Progress()

        let steps = progress.steps()
        steps.add { recorder.record("first") }
        steps.add { recorder.record("second") }
        steps.add { recorder.record("third") }
        try await steps.execute()

        #expect(recorder.calls == ["first", "second", "third"])
        #expect(progress.isFinished)
    }

    @Test func executeSumsStepWeights() async throws {
        let progress = Progress()

        let steps = progress.steps()
        steps.add(weight: 2) {}
        steps.add(weight: 5) {}
        try await steps.execute()

        #expect(progress.totalUnitCount == 7)
        #expect(progress.isFinished)
    }

    @Test func executePassesChildProgressToStep() async throws {
        let progress = Progress()

        let steps = progress.steps()
        steps.add { (child: Progress) in
            child.totalUnitCount = 10
            child.completedUnitCount = 5
        }
        try await steps.execute()

        #expect(progress.isFinished)
    }

    @Test func executeRethrowsStepError() async throws {
        let recorder = Recorder()
        let progress = Progress()

        let steps = progress.steps()
        steps.add { recorder.record("first") }
        steps.add { throw StepFailure() }
        steps.add { recorder.record("third") }

        await #expect(throws: StepFailure.self) {
            try await steps.execute()
        }

        #expect(recorder.calls == ["first"])
        #expect(!progress.isFinished)
    }
}
