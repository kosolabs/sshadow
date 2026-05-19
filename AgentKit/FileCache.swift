import Common
import FileProvider
import Foundation
import OrderedCollections

private let logger = Logger(category: "Session")

typealias Reader =
    @Sendable (
        NSFileProviderItemIdentifier, Range<UInt64>
    ) async throws -> Data

actor FileCache {
    static let prefetchWindow: UInt64 = 2
    static let defaultCapacity: Int = 32

    private let read: Reader
    private let capacity: Int
    private var cache: OrderedDictionary<Chunk, Task<Data, any Error>> = [:]

    init(
        read: @escaping Reader,
        capacity: Int = defaultCapacity
    ) {
        self.read = read
        self.capacity = capacity
    }

    @discardableResult
    func prefetch(_ chunk: Chunk) -> Task<Data, any Error> {
        if let task = cache.removeValue(forKey: chunk) {
            cache[chunk] = task
            return task
        }
        logger.debug("Prefetch \(chunk)")
        let task = Task<Data, any Error> {
            let data = try await read(chunk.file.id, chunk.byteRange)
            logger.debug("Prefetched \(chunk)")
            return data
        }
        insert(chunk, task: task)
        return task
    }

    func fetch(_ chunk: Chunk) async throws -> Data {
        if let task = cache.removeValue(forKey: chunk) {
            cache[chunk] = task
            logger.debug("Cache hit \(chunk)")
            return try await task.value
        }
        logger.debug("Cache miss \(chunk)")
        let task = Task<Data, any Error> {
            try await read(chunk.file.id, chunk.byteRange)
        }
        insert(chunk, task: task)
        return try await task.value
    }

    private func insert(_ chunk: Chunk, task: Task<Data, any Error>) {
        cache[chunk] = task
        if cache.count > capacity {
            cache.removeFirst()
        }
    }
}
