import Foundation

extension Int {
    func alignedDown(to alignment: Int) -> Int {
        (self / alignment) * alignment
    }

    func alignedUp(to alignment: Int) -> Int {
        ((self + alignment - 1) / alignment) * alignment
    }
}

extension NSRange {
    func aligned(to alignment: Int) -> NSRange {
        let location = self.location.alignedDown(to: alignment)
        let end = self.upperBound.alignedUp(to: alignment)
        return NSRange(location..<end)
    }

    func clamped(to limit: Int) -> NSRange {
        let end = min(self.upperBound, limit)
        return NSRange(location..<end)
    }
}

extension Optional where Wrapped == NSRange {
    func clamped(to limit: Int) -> NSRange {
        guard let self = self else {
            return NSRange(location: 0, length: limit)
        }
        return self.clamped(to: limit)
    }
}
