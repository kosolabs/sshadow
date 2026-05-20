import Common
import FileProvider
import Foundation

struct File: Sendable, CustomStringConvertible {
    static let defaultChunkSize: UInt64 = 256 * 1024

    let id: NSFileProviderItemIdentifier
    let name: String
    let size: UInt64
    let chunkSize: UInt64

    init(
        item: Item,
        chunkSize: UInt64 = defaultChunkSize
    ) {
        self.id = NSFileProviderItemIdentifier(item.id)
        self.name = item.name
        self.size = item.size ?? 0
        self.chunkSize = chunkSize
    }

    var chunkCount: UInt64 {
        guard size > 0 else { return 0 }
        return (size + chunkSize - 1) / chunkSize
    }

    func chunk(at index: UInt64) -> Chunk {
        Chunk(file: self, index: index)
    }

    func slice(for byteRange: Range<UInt64>) -> Slice {
        let aligned = byteRange.aligned(to: chunkSize)
        let chunks =
            ((aligned.lowerBound / chunkSize)..<(aligned.upperBound / chunkSize))
            .clamped(to: 0..<chunkCount)
        return Slice(file: self, chunks: chunks)
    }

    func byteRange(forChunks chunks: Range<UInt64>) -> Range<UInt64> {
        ((chunks.lowerBound * chunkSize)..<(chunks.upperBound * chunkSize))
            .clamped(to: 0..<size)
    }

    var description: String {
        let fields = [
            "id: \(id.rawValue)",
            "name: \(name)",
            "size: \(size)",
            "chunkSize: \(chunkSize)",
        ].joined(separator: ", ")
        return "File(\(fields))"
    }

    struct Chunk: Sendable, CustomStringConvertible {
        let file: File
        let index: UInt64

        var byteRange: Range<UInt64> {
            file.byteRange(forChunks: index..<index + 1)
        }

        var key: Key {
            Key(fileId: file.id, index: index)
        }

        struct Key: Hashable, Sendable {
            let fileId: NSFileProviderItemIdentifier
            let index: UInt64
        }

        var description: String {
            "File.Chunk(index: \(index)/\(file.chunkCount), byteRange: \(byteRange), \(file))"
        }
    }

    struct Slice: Sendable, Sequence, CustomStringConvertible {
        let file: File
        let chunks: Range<UInt64>

        var byteRange: Range<UInt64> {
            file.byteRange(forChunks: chunks)
        }

        func makeIterator() -> AnyIterator<Chunk> {
            var index = chunks.lowerBound
            let upperBound = chunks.upperBound
            let file = self.file
            return AnyIterator {
                guard index < upperBound else { return nil }
                defer { index += 1 }
                return file.chunk(at: index)
            }
        }

        var description: String {
            "File.Slice(chunks: \(chunks)/\(file.chunkCount), byteRange: \(byteRange), \(file))"
        }
    }
}
