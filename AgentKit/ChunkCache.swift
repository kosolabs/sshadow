import Common
import FileProvider
import Foundation

private let logger = Logger(category: "Session")

typealias ChunkReader =
    @Sendable (
        NSFileProviderItemIdentifier, Range<UInt64>
    ) async throws -> Data

actor ChunkedFileCachePool {
    private var entries: [String: ChunkedFileCache] = [:]

    func cache(
        for file: ChunkedFile,
        read: @escaping ChunkReader
    ) -> ChunkedFileCache {
        let key = file.id.rawValue
        if let existing = entries[key] {
            return existing
        }
        let cache = ChunkedFileCache(file: file, read: read)
        entries[key] = cache
        return cache
    }
}

actor ChunkedFileCache {
    private let file: ChunkedFile
    private let read: ChunkReader
    private var cache: [UInt64: Task<Data, any Error>] = [:]

    init(file: ChunkedFile, read: @escaping ChunkReader) {
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
