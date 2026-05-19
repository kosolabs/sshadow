import Common
import FileProvider
import Foundation
import Testing

@testable import AgentKit

private func file(size: UInt64 = 10 * File.defaultChunkSize) -> File {
    File(info: FileInfo(
        id: UUID().uuidString,
        parentId: UUID().uuidString,
        name: "file",
        type: .file,
        size: size,
        permissions: 0o644,
        accessTime: nil,
        modifyTime: nil,
        createTime: nil
    ))
}

private actor CallLog {
    private var calls: [String: Int] = [:]

    private func key(_ itemId: NSFileProviderItemIdentifier, _ chunkId: UInt64) -> String {
        "\(itemId.rawValue):\(chunkId)"
    }

    func record(_ itemId: NSFileProviderItemIdentifier, _ chunkId: UInt64) {
        calls[key(itemId, chunkId), default: 0] += 1
    }

    func count(for itemId: NSFileProviderItemIdentifier, _ chunkId: UInt64) -> Int {
        calls[key(itemId, chunkId)] ?? 0
    }
}

private func makeCache(log: CallLog, capacity: Int) -> FileCache {
    FileCache(read: { itemId, range in
        await log.record(itemId, range.lowerBound / File.defaultChunkSize)
        return Data()
    }, capacity: capacity)
}

struct FileCacheTests {
    @Test func cachesRepeatedFetch() async throws {
        let log = CallLog()
        let cache = makeCache(log: log, capacity: 2)
        let f = file()
        _ = try await cache.fetch(Chunk(file: f, id: 0))
        _ = try await cache.fetch(Chunk(file: f, id: 0))
        #expect(await log.count(for: f.id, 0) == 1)
    }

    @Test func evictsOldestWhenOverCapacity() async throws {
        let log = CallLog()
        let cache = makeCache(log: log, capacity: 2)
        let f = file()
        _ = try await cache.fetch(Chunk(file: f, id: 0))
        _ = try await cache.fetch(Chunk(file: f, id: 1))
        _ = try await cache.fetch(Chunk(file: f, id: 2))
        _ = try await cache.fetch(Chunk(file: f, id: 0))
        #expect(await log.count(for: f.id, 0) == 2)
        #expect(await log.count(for: f.id, 1) == 1)
        #expect(await log.count(for: f.id, 2) == 1)
    }

    @Test func hitBumpsRecency() async throws {
        let log = CallLog()
        let cache = makeCache(log: log, capacity: 2)
        let f = file()
        _ = try await cache.fetch(Chunk(file: f, id: 0))
        _ = try await cache.fetch(Chunk(file: f, id: 1))
        _ = try await cache.fetch(Chunk(file: f, id: 0))
        _ = try await cache.fetch(Chunk(file: f, id: 2))
        _ = try await cache.fetch(Chunk(file: f, id: 0))
        _ = try await cache.fetch(Chunk(file: f, id: 1))
        #expect(await log.count(for: f.id, 0) == 1)
        #expect(await log.count(for: f.id, 1) == 2)
        #expect(await log.count(for: f.id, 2) == 1)
    }

    @Test func separatesEntriesByFile() async throws {
        let log = CallLog()
        let cache = makeCache(log: log, capacity: 4)
        let f0 = file()
        let f1 = file()
        _ = try await cache.fetch(Chunk(file: f0, id: 0))
        _ = try await cache.fetch(Chunk(file: f1, id: 0))
        _ = try await cache.fetch(Chunk(file: f0, id: 0))
        _ = try await cache.fetch(Chunk(file: f1, id: 0))
        #expect(await log.count(for: f0.id, 0) == 1)
        #expect(await log.count(for: f1.id, 0) == 1)
    }

    @Test func evictsAcrossFiles() async throws {
        let log = CallLog()
        let cache = makeCache(log: log, capacity: 2)
        let f0 = file()
        let f1 = file()
        let f2 = file()
        _ = try await cache.fetch(Chunk(file: f0, id: 0))
        _ = try await cache.fetch(Chunk(file: f1, id: 0))
        _ = try await cache.fetch(Chunk(file: f2, id: 0))
        _ = try await cache.fetch(Chunk(file: f0, id: 0))
        #expect(await log.count(for: f0.id, 0) == 2)
        #expect(await log.count(for: f1.id, 0) == 1)
        #expect(await log.count(for: f2.id, 0) == 1)
    }
}
