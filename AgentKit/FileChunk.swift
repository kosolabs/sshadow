import Common
import Foundation

enum FileChunk {
    static let size: UInt64 = 64 * 1024

    static func chunkRange(
        for range: Range<UInt64>
    ) -> Range<UInt64> {
        let aligned = range.aligned(to: size)
        return (aligned.lowerBound / size)..<(aligned.upperBound / size)
    }

    static func byteRange(
        for chunks: Range<UInt64>,
        fileSize: UInt64
    ) -> Range<UInt64> {
        let range = (chunks.lowerBound * size)..<(chunks.upperBound * size)
        return range.clamped(to: fileSize)
    }

    static func byteRange(
        for chunk: UInt64,
        fileSize: UInt64
    ) -> Range<UInt64> {
        byteRange(for: chunk..<chunk + 1, fileSize: fileSize)
    }
}
