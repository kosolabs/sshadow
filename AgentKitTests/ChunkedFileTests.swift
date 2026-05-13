import Common
import FileProvider
import Foundation
import Testing

@testable import AgentKit

private func info(size: UInt64) -> FileInfo {
    FileInfo(
        id: UUID().uuidString,
        parentId: UUID().uuidString,
        name: "file",
        type: .file,
        size: size,
        permissions: 0o644,
        accessTime: nil,
        modifyTime: nil,
        createTime: nil
    )
}

struct ChunkedFileTests {
    struct ChunkRangeTests {
        @Test func singleChunkForSmallRange() {
            let file = ChunkedFile(info: info(size: 1024 * 1024))
            let chunks = file.chunkRange(for: 0..<100)
            #expect(chunks == 0..<1)
        }

        @Test func singleChunkWhenRangeWithinFirstChunk() {
            let file = ChunkedFile(info: info(size: 1024 * 1024))
            let chunks = file.chunkRange(for: 10 * 1024..<20 * 1024)
            #expect(chunks == 0..<1)
        }

        @Test func multipleChunksForLargeRange() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 10))
            let range: Range<UInt64> = (size - 1000)..<(size + 1000)
            let chunks = file.chunkRange(for: range)
            #expect(chunks.count > 1)
            #expect(chunks.lowerBound * file.chunkSize <= range.lowerBound)
            #expect(chunks.upperBound * file.chunkSize >= range.upperBound)
        }

        @Test func smallRange() {
            let file = ChunkedFile(info: info(size: 1024 * 1024))
            let chunks = file.chunkRange(for: 0..<1)
            #expect(chunks == 0..<1)
        }

        @Test func exactChunkBoundary() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size))
            let chunks = file.chunkRange(for: 0..<size)
            #expect(chunks == 0..<1)
        }

        @Test func rangeSpanningChunkBoundary() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 10))
            let chunks = file.chunkRange(for: (size - 1)..<(size + 1))
            #expect(chunks == 0..<2)
        }

        @Test func clampsToChunkCount() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 3))
            let chunks = file.chunkRange(for: 0..<(size * 5))
            #expect(chunks == 0..<3)
        }

        @Test func clampsBeyondFileEnd() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 2 + 100))
            let chunks = file.chunkRange(for: (size * 2)..<(size * 5))
            #expect(chunks == 2..<3)
        }

        @Test func emptyForEmptyFile() {
            let file = ChunkedFile(info: info(size: 0))
            let chunks = file.chunkRange(for: 0..<100)
            #expect(chunks.isEmpty)
        }
    }

    struct ByteRangeForChunksTests {
        @Test func singleChunkInLargeFile() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 10))
            let range = file.byteRange(for: 0..<1)
            #expect(range == 0..<size)
        }

        @Test func multipleChunks() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 10))
            let range = file.byteRange(for: 2..<5)
            #expect(range == (2 * size)..<(5 * size))
        }

        @Test func clampsToFileSize() {
            let size = ChunkedFile.defaultChunkSize
            let fileSize = size * 2 + 100
            let file = ChunkedFile(info: info(size: fileSize))
            let range = file.byteRange(for: 0..<3)
            #expect(range == 0..<fileSize)
        }

        @Test func lastPartialChunk() {
            let size = ChunkedFile.defaultChunkSize
            let fileSize = size + 500
            let file = ChunkedFile(info: info(size: fileSize))
            let range = file.byteRange(for: 1..<2)
            #expect(range == size..<fileSize)
        }
    }

    struct ByteRangeForIndexTests {
        @Test func firstChunk() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 10))
            let range = file.byteRange(for: 0)
            #expect(range == 0..<size)
        }

        @Test func middleChunk() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 10))
            let range = file.byteRange(for: 3)
            #expect(range == (3 * size)..<(4 * size))
        }

        @Test func lastPartialChunk() {
            let size = ChunkedFile.defaultChunkSize
            let fileSize = size * 3 + 1000
            let file = ChunkedFile(info: info(size: fileSize))
            let range = file.byteRange(for: 3)
            #expect(range == (3 * size)..<fileSize)
        }

        @Test func lastFullChunk() {
            let size = ChunkedFile.defaultChunkSize
            let fileSize = size * 4
            let file = ChunkedFile(info: info(size: fileSize))
            let range = file.byteRange(for: 3)
            #expect(range == (3 * size)..<(4 * size))
        }

        @Test func emptyWhenBeyondFileSize() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 3))
            let range = file.byteRange(for: 5)
            #expect(range.isEmpty)
        }
    }

    struct ByteOffsetTests {
        @Test func firstChunk() {
            let file = ChunkedFile(info: info(size: 1024 * 1024 * 10))
            #expect(file.byteOffset(for: 0) == 0)
        }

        @Test func middleChunk() {
            let size = ChunkedFile.defaultChunkSize
            let file = ChunkedFile(info: info(size: size * 10))
            #expect(file.byteOffset(for: 3) == 3 * size)
        }

        @Test func customChunkSize() {
            let file = ChunkedFile(info: info(size: 5000), chunkSize: 500)
            #expect(file.byteOffset(for: 4) == 2000)
        }
    }

    struct RoundTripTests {
        @Test func chunkRangeThenByteRangeCoversOriginal() {
            let cases: [(Range<UInt64>, UInt64)] = [
                (UInt64(10 * 1024)..<UInt64(20 * 1024), 1024 * 1024),
                (0..<100, 1024 * 1024),
                (65000..<65200, 1024 * 1024),
                (500_000..<600_000, 1024 * 1024),
                (100..<150, 200),
            ]

            for (range, fileSize) in cases {
                let file = ChunkedFile(info: info(size: fileSize))
                let chunks = file.chunkRange(for: range)
                let bytes = file.byteRange(for: chunks)

                #expect(bytes.lowerBound <= range.lowerBound)
                #expect(bytes.upperBound >= min(range.upperBound, fileSize))
                #expect(bytes.lowerBound % file.chunkSize == 0)
            }
        }
    }
}
