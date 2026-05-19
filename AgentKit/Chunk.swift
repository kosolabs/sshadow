import Common
import FileProvider
import Foundation

struct Chunk: Hashable, Sendable, CustomStringConvertible {
    let file: File
    let id: UInt64

    var byteRange: Range<UInt64> {
        file.byteRange(for: id)
    }

    static func == (lhs: Chunk, rhs: Chunk) -> Bool {
        lhs.file.id == rhs.file.id && lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(file.id)
        hasher.combine(id)
    }

    var description: String {
        let fields = [
            "\(id)/\(file.chunkCount)",
            "range: \(byteRange) / \(file.size)",
            "item: \(file.id.rawValue)",
            "name: \(file.name)",
            "size: \(file.size)",
            "chunkSize: \(file.chunkSize)",
        ].joined(separator: ", ")
        return "Chunk(\(fields))"
    }
}
