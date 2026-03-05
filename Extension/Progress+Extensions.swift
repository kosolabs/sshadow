import Foundation

extension Progress {
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
        return try await perform(child)
    }
}
