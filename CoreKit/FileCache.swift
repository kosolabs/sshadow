import Common
import FileProvider
import Foundation
import OrderedCollections

private let logger = Logger(category: "Session")

typealias Reader =
    @Sendable (
        NSFileProviderItemIdentifier, Range<UInt64>
    ) async throws -> Data

typealias FetchTask = Task<Data, any Error>

actor FileCache {
    static let prefetchWindow: UInt64 = 2
    static let defaultCapacity: Int = 32

    private let read: Reader
    private let capacity: Int
    private var cache: OrderedDictionary<File.Chunk.Key, FetchTask> = [:]

    init(
        read: @escaping Reader,
        capacity: Int = defaultCapacity
    ) {
        self.read = read
        self.capacity = capacity
    }

    @discardableResult
    func prefetch(_ chunk: File.Chunk) -> FetchTask {
        if let task = cache.removeValue(forKey: chunk.key) {
            cache[chunk.key] = task
            logger.debug("Cache hit \(chunk)")
            return task
        }
        logger.debug("Cache miss \(chunk)")
        let task = FetchTask {
            try await read(chunk.file.id, chunk.byteRange)
        }
        insert(chunk, task: task)
        return task
    }

    func fetch(_ chunk: File.Chunk) async throws -> Data {
        try await prefetch(chunk).value
    }

    func invalidate(_ item: NSFileProviderItemIdentifier) {
        for key in Array(cache.keys) where key.fileId == item {
            let task = cache.removeValue(forKey: key)
            task?.cancel()
        }
    }

    private func insert(_ chunk: File.Chunk, task: FetchTask) {
        cache[chunk.key] = task
        if cache.count > capacity {
            cache.removeFirst()
        }
    }
}
