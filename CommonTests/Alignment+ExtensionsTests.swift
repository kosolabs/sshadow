import Testing
import Foundation

@testable import Common

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

struct RangeAlignedTests {
    @Test func alignedRangeAlreadyAligned() {
        #expect((0..<512).aligned(to: 512) == 0..<512)
    }

    @Test func locationIsFlooredAndEndIsCeiled() {
        #expect((100..<200).aligned(to: 512) == 0..<512)
    }

    @Test func rangeSpanningMultipleAlignmentBlocks() {
        #expect((100..<1100).aligned(to: 512) == 0..<1536)
    }

    @Test func zeroLengthRange() {
        #expect((256..<256).aligned(to: 512) == 0..<512)
    }

    @Test func alignmentOfOne() {
        #expect((3..<8).aligned(to: 1) == 3..<8)
    }

    @Test func largeAlignment() {
        #expect((1..<2).aligned(to: 4096) == 0..<4096)
    }
}

struct RangeClampedTests {
    @Test func endClampedToLimit() {
        #expect((0..<400).clamped(to: 300) == 0..<300)
    }

    @Test func endBelowLimit() {
        #expect((0..<400).clamped(to: 512) == 0..<400)
    }

    @Test func endExactlyAtLimit() {
        #expect((0..<512).clamped(to: 512) == 0..<512)
    }

    @Test func locationAndEndBothClampedToLimit() {
        #expect((100..<600).clamped(to: 200) == 100..<200)
    }
}

struct RangeAlignedAndClampedTests {
    @Test func alignedAndClampedToLimit() {
        #expect((0..<400).aligned(to: 512).clamped(to: 400) == 0..<400)
    }

    @Test func alignedAndLimitIsExactMultiple() {
        #expect((0..<512).aligned(to: 512).clamped(to: 512) == 0..<512)
    }

    @Test func locationFlooredAndEndClampedToLimit() {
        #expect((300..<600).aligned(to: 512).clamped(to: 512) == 0..<512)
    }

    @Test func alignedEndExceedsLimitAndIsClamped() {
        #expect((0..<100).aligned(to: 512).clamped(to: 300) == 0..<300)
    }
}
