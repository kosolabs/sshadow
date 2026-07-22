import Common
import FileProvider
import Foundation
import Testing

@testable import CoreKit

private func item(size: UInt64) -> Item {
    Item(
        id: UUID().uuidString,
        parentId: UUID().uuidString,
        name: "file",
        kind: .file,
        size: size,
        flags: .rw,
        accessTime: nil,
        modifyTime: nil,
        createTime: nil,
        enumeratedAt: nil
    )
}

struct FileTests {
    struct SliceTests {
        @Test func singleChunkForSmallRange() {
            let file = File(item: item(size: 1024 * 1024))
            let slice = file.slice(for: 0..<100)
            #expect(slice.chunks == 0..<1)
        }

        @Test func singleChunkWhenRangeWithinFirstChunk() {
            let file = File(item: item(size: 1024 * 1024))
            let slice = file.slice(for: 10 * 1024..<20 * 1024)
            #expect(slice.chunks == 0..<1)
        }

        @Test func multipleChunksForLargeRange() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 10))
            let range: Range<UInt64> = (size - 1000)..<(size + 1000)
            let slice = file.slice(for: range)
            #expect(slice.chunks.count > 1)
            #expect(slice.chunks.lowerBound * file.chunkSize <= range.lowerBound)
            #expect(slice.chunks.upperBound * file.chunkSize >= range.upperBound)
        }

        @Test func smallRange() {
            let file = File(item: item(size: 1024 * 1024))
            let slice = file.slice(for: 0..<1)
            #expect(slice.chunks == 0..<1)
        }

        @Test func exactChunkBoundary() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size))
            let slice = file.slice(for: 0..<size)
            #expect(slice.chunks == 0..<1)
        }

        @Test func rangeSpanningChunkBoundary() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 10))
            let slice = file.slice(for: (size - 1)..<(size + 1))
            #expect(slice.chunks == 0..<2)
        }

        @Test func clampsToChunkCount() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 3))
            let slice = file.slice(for: 0..<(size * 5))
            #expect(slice.chunks == 0..<3)
        }

        @Test func clampsBeyondFileEnd() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 2 + 100))
            let slice = file.slice(for: (size * 2)..<(size * 5))
            #expect(slice.chunks == 2..<3)
        }

        @Test func emptyForEmptyFile() {
            let file = File(item: item(size: 0))
            let slice = file.slice(for: 0..<100)
            #expect(slice.chunks.isEmpty)
        }
    }

    struct SliceByteRangeTests {
        @Test func singleChunkInLargeFile() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 10))
            let slice = File.Slice(file: file, chunks: 0..<1)
            #expect(slice.byteRange == 0..<size)
        }

        @Test func multipleChunks() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 10))
            let slice = File.Slice(file: file, chunks: 2..<5)
            #expect(slice.byteRange == (2 * size)..<(5 * size))
        }

        @Test func clampsToFileSize() {
            let size = File.defaultChunkSize
            let fileSize = size * 2 + 100
            let file = File(item: item(size: fileSize))
            let slice = File.Slice(file: file, chunks: 0..<3)
            #expect(slice.byteRange == 0..<fileSize)
        }

        @Test func lastPartialChunk() {
            let size = File.defaultChunkSize
            let fileSize = size + 500
            let file = File(item: item(size: fileSize))
            let slice = File.Slice(file: file, chunks: 1..<2)
            #expect(slice.byteRange == size..<fileSize)
        }
    }

    struct ChunkByteRangeTests {
        @Test func firstChunk() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 10))
            #expect(file.chunk(at: 0).byteRange == 0..<size)
        }

        @Test func middleChunk() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 10))
            #expect(file.chunk(at: 3).byteRange == (3 * size)..<(4 * size))
        }

        @Test func lastPartialChunk() {
            let size = File.defaultChunkSize
            let fileSize = size * 3 + 1000
            let file = File(item: item(size: fileSize))
            #expect(file.chunk(at: 3).byteRange == (3 * size)..<fileSize)
        }

        @Test func lastFullChunk() {
            let size = File.defaultChunkSize
            let fileSize = size * 4
            let file = File(item: item(size: fileSize))
            #expect(file.chunk(at: 3).byteRange == (3 * size)..<(4 * size))
        }

        @Test func emptyWhenBeyondFileSize() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 3))
            #expect(file.chunk(at: 5).byteRange.isEmpty)
        }

        @Test func customChunkSize() {
            let file = File(item: item(size: 5000), chunkSize: 500)
            #expect(file.chunk(at: 4).byteRange.lowerBound == 2000)
        }
    }

    struct SliceIterationTests {
        @Test func iteratesChunksInOrder() {
            let size = File.defaultChunkSize
            let file = File(item: item(size: size * 10))
            let slice = file.slice(for: (size - 1)..<(size * 3 + 1))
            let indices = slice.map(\.index)
            #expect(indices == [0, 1, 2, 3])
        }

        @Test func chunksCarryFileId() {
            let file = File(item: item(size: File.defaultChunkSize * 3))
            let slice = file.slice(for: 0..<file.size)
            #expect(slice.allSatisfy { $0.file.id == file.id })
        }
    }

    struct RoundTripTests {
        @Test func sliceByteRangeCoversOriginalRange() {
            let cases: [(Range<UInt64>, UInt64)] = [
                (UInt64(10 * 1024)..<UInt64(20 * 1024), 1024 * 1024),
                (0..<100, 1024 * 1024),
                (65000..<65200, 1024 * 1024),
                (500_000..<600_000, 1024 * 1024),
                (100..<150, 200),
            ]

            for (range, fileSize) in cases {
                let file = File(item: item(size: fileSize))
                let slice = file.slice(for: range)
                let bytes = slice.byteRange

                #expect(bytes.lowerBound <= range.lowerBound)
                #expect(bytes.upperBound >= min(range.upperBound, fileSize))
                #expect(bytes.lowerBound % file.chunkSize == 0)
            }
        }
    }
}
