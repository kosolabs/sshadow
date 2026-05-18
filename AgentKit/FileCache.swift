import Common
import FileProvider
import Foundation

private let logger = Logger(category: "Session")

typealias Reader =
    @Sendable (
        NSFileProviderItemIdentifier, Range<UInt64>
    ) async throws -> Data

actor FileCachePool {
    private var entries: [String: FileCache] = [:]

    func cache(
        for file: File,
        read: @escaping Reader
    ) -> FileCache {
        let key = file.id.rawValue
        if let existing = entries[key] {
            return existing
        }
        let cache = FileCache(file: file, read: read)
        entries[key] = cache
        return cache
    }
}

actor FileCache {
    private let file: File
    private let read: Reader
    private var cache: [UInt64: Task<Data, any Error>] = [:]

    init(file: File, read: @escaping Reader) {
        self.file = file
        self.read = read
    }

    @discardableResult
    func fetch(chunkId: UInt64) async throws -> Data {
        if let task = cache[chunkId] {
            logger.debug("Cache hit \(file)[\(chunkId)]")
            return try await task.value
        }

        logger.debug("Caching \(file)[\(chunkId)]")
        let task = Task<Data, any Error> {
            try await read(file.id, file.byteRange(for: chunkId))
        }
        cache[chunkId] = task
        let data = try await task.value

        logger.debug("Cached \(file)[\(chunkId)]")
        return data
    }
}
