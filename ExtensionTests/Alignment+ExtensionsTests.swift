import Testing
import Foundation

@testable import Extension

struct AlignedDownTests {

    @Test func alreadyAligned() {
        #expect(512.alignedDown(to: 512) == 512)
    }

    @Test func floorsToPreviousMultiple() {
        #expect(100.alignedDown(to: 512) == 0)
        #expect(513.alignedDown(to: 512) == 512)
        #expect(1023.alignedDown(to: 512) == 512)
    }

    @Test func alignmentOfOne() {
        #expect(7.alignedDown(to: 1) == 7)
    }

    @Test func zero() {
        #expect(0.alignedDown(to: 512) == 0)
    }
}

struct AlignedUpTests {

    @Test func alreadyAligned() {
        #expect(512.alignedUp(to: 512) == 512)
    }

    @Test func ceilsToNextMultiple() {
        #expect(1.alignedUp(to: 512) == 512)
        #expect(511.alignedUp(to: 512) == 512)
        #expect(513.alignedUp(to: 512) == 1024)
    }

    @Test func alignmentOfOne() {
        #expect(7.alignedUp(to: 1) == 7)
    }

    @Test func zero() {
        #expect(0.alignedUp(to: 512) == 0)
    }
}

struct NSRangeAlignedTests {

    @Test func alignedRangeAlreadyAligned() {
        #expect(NSRange(location: 0, length: 512).aligned(to: 512) == NSRange(0..<512))
    }

    @Test func locationIsFlooredAndEndIsCeiled() {
        #expect(NSRange(location: 100, length: 100).aligned(to: 512) == NSRange(0..<512))
    }

    @Test func rangeSpanningMultipleAlignmentBlocks() {
        #expect(NSRange(location: 100, length: 1000).aligned(to: 512) == NSRange(0..<1536))
    }

    @Test func zeroLengthRange() {
        #expect(NSRange(location: 256, length: 0).aligned(to: 512) == NSRange(0..<512))
    }

    @Test func alignmentOfOne() {
        #expect(NSRange(location: 3, length: 5).aligned(to: 1) == NSRange(3..<8))
    }

    @Test func largeAlignment() {
        #expect(NSRange(location: 1, length: 1).aligned(to: 4096) == NSRange(0..<4096))
    }
}

struct NSRangeClampedTests {

    @Test func endClampedToLimit() {
        #expect(NSRange(location: 0, length: 400).clamped(to: 300) == NSRange(0..<300))
    }

    @Test func endBelowLimit() {
        #expect(NSRange(location: 0, length: 400).clamped(to: 512) == NSRange(0..<400))
    }

    @Test func endExactlyAtLimit() {
        #expect(NSRange(location: 0, length: 512).clamped(to: 512) == NSRange(0..<512))
    }

    @Test func locationAndEndBothClampedToLimit() {
        #expect(NSRange(location: 100, length: 500).clamped(to: 200) == NSRange(100..<200))
    }
}

struct NSRangeAlignedAndClampedTests {

    @Test func alignedAndClampedToLimit() {
        #expect(NSRange(location: 0, length: 400).aligned(to: 512).clamped(to: 400) == NSRange(0..<400))
    }

    @Test func alignedAndLimitIsExactMultiple() {
        #expect(NSRange(location: 0, length: 512).aligned(to: 512).clamped(to: 512) == NSRange(0..<512))
    }

    @Test func locationFlooredAndEndClampedToLimit() {
        #expect(NSRange(location: 300, length: 300).aligned(to: 512).clamped(to: 512) == NSRange(0..<512))
    }

    @Test func alignedEndExceedsLimitAndIsClamped() {
        #expect(NSRange(location: 0, length: 100).aligned(to: 512).clamped(to: 300) == NSRange(0..<300))
    }
}
