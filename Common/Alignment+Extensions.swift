import Foundation

extension BinaryInteger {
    public func alignedDown(to alignment: Self) -> Self {
        (self / alignment) * alignment
    }

    public func alignedUp(to alignment: Self) -> Self {
        ((self + alignment - 1) / alignment) * alignment
    }
}

extension Range<UInt64> {
    public var offset: Bound { lowerBound }
    public var length: Bound { upperBound - lowerBound }
    
    public func asNSRange() -> NSRange {
        NSRange(self)
    }

    public func aligned(to alignment: UInt64) -> Range<UInt64> {
        let location = lowerBound.alignedDown(to: alignment)
        let end = upperBound.alignedUp(to: alignment)
        return location..<end
    }

    public func clamped(to limit: UInt64) -> Range<UInt64> {
        let end = Swift.max(Swift.min(upperBound, limit), lowerBound)
        return lowerBound..<end
    }
}

extension NSRange {
    public func asRange() -> Range<UInt64> {
        UInt64(lowerBound)..<UInt64(upperBound)
    }
}
