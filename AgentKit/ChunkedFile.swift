import Common
import FileProvider
import Foundation

struct ChunkedFile: CustomStringConvertible {
    static let defaultChunkSize: UInt64 = 1024 * 1024

    let info: FileInfo
    let chunkSize: UInt64

    init(
        info: FileInfo,
        chunkSize: UInt64 = defaultChunkSize
    ) {
        self.info = info
        self.chunkSize = chunkSize
    }

    var id: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(info.id)
    }

    var name: String {
        info.name
    }

    var size: UInt64 {
        info.size
    }

    var chunkCount: UInt64 {
        guard info.size > 0 else { return 0 }
        return (info.size + chunkSize - 1) / chunkSize
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
        return range.clamped(to: 0..<info.size)
    }

    func byteRange(for chunk: UInt64) -> Range<UInt64> {
        byteRange(for: chunk..<chunk + 1)
    }

    func byteOffset(for chunk: UInt64) -> UInt64 {
        chunk * chunkSize
    }

    var description: String {
        "ChunkedFile(id: \(info.id), name: \(name), size: \(size), chunks: \(chunkCount)@\(chunkSize)b)"
    }
}
