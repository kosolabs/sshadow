import FileProvider
import Foundation
import SwiftData

@Model
public class SSHChunk {
    public static let size: UInt64 = 64 * 1024

    var rawItemId: String
    var index: UInt64

    public init(itemId: NSFileProviderItemIdentifier, index: UInt64) {
        self.rawItemId = itemId.rawValue
        self.index = index
    }

    public var itemId: NSFileProviderItemIdentifier {
        get { NSFileProviderItemIdentifier(rawItemId) }
        set { rawItemId = newValue.rawValue }
    }

    public static func chunkRange(
        for range: Range<UInt64>
    ) -> Range<UInt64> {
        let aligned = range.aligned(to: size)
        return (aligned.lowerBound / size)..<(aligned.upperBound / size)
    }

    public static func byteRange(
        for chunks: Range<UInt64>,
        fileSize: UInt64
    ) -> Range<UInt64> {
        let range = (chunks.lowerBound * size)..<(chunks.upperBound * size)
        return range.clamped(to: fileSize)
    }

    public static func byteRange(
        for chunk: UInt64,
        fileSize: UInt64
    ) -> Range<UInt64> {
        byteRange(for: chunk..<chunk + 1, fileSize: fileSize)
    }
}
