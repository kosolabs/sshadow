import Foundation
import Testing

@testable import Common

struct SSHChunkTests {
    struct ChunkRangeTests {
        @Test func singleChunkForSmallRange() {
            let chunks = FileChunk.chunkRange(for: 0..<100)
            #expect(chunks == 0..<1)
        }

        @Test func singleChunkWhenRangeWithinFirstChunk() {
            let chunks = FileChunk.chunkRange(for: 10 * 1024..<20 * 1024)
            #expect(chunks == 0..<1)
        }

        @Test func multipleChunksForLargeRange() {
            let chunks = FileChunk.chunkRange(for: 500_000..<600_000)
            #expect(chunks.count > 1)
            #expect(chunks.lowerBound * FileChunk.size <= 500_000)
            #expect(chunks.upperBound * FileChunk.size >= 600_000)
        }

        @Test func smallRange() {
            let chunks = FileChunk.chunkRange(for: 0..<1)
            #expect(chunks == 0..<1)
        }

        @Test func exactChunkBoundary() {
            let size = FileChunk.size
            let chunks = FileChunk.chunkRange(for: 0..<size)
            #expect(chunks == 0..<1)
        }

        @Test func rangeSpanningChunkBoundary() {
            let size = FileChunk.size
            let chunks = FileChunk.chunkRange(for: (size - 1)..<(size + 1))
            #expect(chunks == 0..<2)
        }
    }

    struct ByteRangeForChunksTests {
        @Test func singleChunkInLargeFile() {
            let size = FileChunk.size
            let range = FileChunk.byteRange(for: 0..<1, fileSize: size * 10)
            #expect(range == 0..<size)
        }

        @Test func multipleChunks() {
            let size = FileChunk.size
            let range = FileChunk.byteRange(for: 2..<5, fileSize: size * 10)
            #expect(range == (2 * size)..<(5 * size))
        }

        @Test func clampsToFileSize() {
            let size = FileChunk.size
            let fileSize = size * 2 + 100
            let range = FileChunk.byteRange(for: 0..<3, fileSize: fileSize)
            #expect(range == 0..<fileSize)
        }

        @Test func lastPartialChunk() {
            let size = FileChunk.size
            let fileSize = size + 500
            let range = FileChunk.byteRange(for: 1..<2, fileSize: fileSize)
            #expect(range == size..<fileSize)
        }
    }

    struct ByteRangeForIndexTests {
        @Test func firstChunk() {
            let size = FileChunk.size
            let range = FileChunk.byteRange(for: 0, fileSize: size * 10)
            #expect(range == 0..<size)
        }

        @Test func middleChunk() {
            let size = FileChunk.size
            let range = FileChunk.byteRange(for: 3, fileSize: size * 10)
            #expect(range == (3 * size)..<(4 * size))
        }

        @Test func lastPartialChunk() {
            let size = FileChunk.size
            let fileSize = size * 3 + 1000
            let range = FileChunk.byteRange(for: 3, fileSize: fileSize)
            #expect(range == (3 * size)..<fileSize)
        }

        @Test func lastFullChunk() {
            let size = FileChunk.size
            let fileSize = size * 4
            let range = FileChunk.byteRange(for: 3, fileSize: fileSize)
            #expect(range == (3 * size)..<(4 * size))
        }

        @Test func emptyWhenBeyondFileSize() {
            let size = FileChunk.size
            let range = FileChunk.byteRange(for: 5, fileSize: size * 3)
            #expect(range.isEmpty)
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
                let chunks = FileChunk.chunkRange(for: range)
                let bytes = FileChunk.byteRange(for: chunks, fileSize: fileSize)

                #expect(bytes.lowerBound <= range.lowerBound)
                #expect(bytes.upperBound >= min(range.upperBound, fileSize))
                #expect(bytes.lowerBound % FileChunk.size == 0)
            }
        }
    }
}
