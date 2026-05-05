import Common
import FileProvider
import Foundation

struct ChunkedFile: CustomStringConvertible {
    static let defaultChunkSize: UInt64 = 1024 * 1024

    let id: NSFileProviderItemIdentifier
    let path: String
    let size: UInt64
    let chunkSize: UInt64

    init(
        id: NSFileProviderItemIdentifier,
        path: String,
        size: UInt64,
        chunkSize: UInt64 = defaultChunkSize
    ) {
        self.id = id
        self.path = path
        self.size = size
        self.chunkSize = chunkSize
    }

    var chunkCount: UInt64 {
        guard size > 0 else { return 0 }
        return (size + chunkSize - 1) / chunkSize
    }

    func chunkRange(for range: Range<UInt64>) -> Range<UInt64> {
        let aligned = range.aligned(to: chunkSize)
        return
            ((aligned.lowerBound / chunkSize)..<(aligned.upperBound / chunkSize))
            .clamped(to: 0..<chunkCount)
    }

    func byteRange(for chunks: Range<UInt64>) -> Range<UInt64> {
        let range =
            (chunks.lowerBound * chunkSize)..<(chunks.upperBound * chunkSize)
        return range.clamped(to: 0..<size)
    }

    func byteRange(for chunk: UInt64) -> Range<UInt64> {
        byteRange(for: chunk..<chunk + 1)
    }

    func byteOffset(for chunk: UInt64) -> UInt64 {
        chunk * chunkSize
    }

    var description: String {
        "ChunkedFile(id: \(id), path: \(path), size: \(size), chunks: \(chunkCount)@\(chunkSize)b)"
    }
}
