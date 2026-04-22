import Foundation

extension Progress {
    struct Step {
        let weight: Int64
        let action: (Progress) async throws -> Void
    }

    class Steps {
        let progress: Progress
        var steps: [Step] = []

        init(progress: Progress) {
            self.progress = progress
        }

        func add(
            weight: Int64 = 1,
            action: @escaping () async throws -> Void
        ) {
            add(weight: weight, action: { _ in try await action() })
        }

        func add(
            weight: Int64 = 1,
            action: @escaping (Progress) async throws -> Void
        ) {
            steps.append(Step(weight: weight, action: action))
        }

        func execute() async throws {
            progress.totalUnitCount = steps.reduce(0) { $0 + $1.weight }
            for step in steps {
                try await progress.withChild(pendingUnitCount: step.weight) {
                    child in
                    try await step.action(child)
                }
            }
        }
    }

    func steps() -> Steps {
        Steps(progress: self)
    }

    func withChild<T>(
        pendingUnitCount: Int64 = 1,
        perform: () throws -> T
    ) throws -> T {
        let child = Progress(totalUnitCount: 1)
        addChild(child, withPendingUnitCount: pendingUnitCount)
        defer { child.completedUnitCount = child.totalUnitCount }
        return try perform()
    }

    func withChild<T>(
        pendingUnitCount: Int64 = 1,
        perform: (Progress) throws -> T
    ) throws -> T {
        let child = Progress(totalUnitCount: 1)
        addChild(child, withPendingUnitCount: pendingUnitCount)
        return try perform(child)
    }

    func withChild<T>(
        pendingUnitCount: Int64 = 1,
        perform: () async throws -> T
    ) async throws -> T {
        let child = Progress(totalUnitCount: 1)
        addChild(child, withPendingUnitCount: pendingUnitCount)
        defer { child.completedUnitCount = child.totalUnitCount }
        return try await perform()
    }

    func withChild<T>(
        pendingUnitCount: Int64 = 1,
        perform: (Progress) async throws -> T
    ) async throws -> T {
        let child = Progress(totalUnitCount: 1)
        addChild(child, withPendingUnitCount: pendingUnitCount)
        defer { child.completedUnitCount = child.totalUnitCount }
        return try await perform(child)
    }
}
