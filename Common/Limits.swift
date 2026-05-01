public struct Limits {
    public static let defaultBufferSize: UInt64 = 102400

    public let maxReadLength: UInt64
    public let maxWriteLength: UInt64
    
    public init(maxReadLength: UInt64, maxWriteLength: UInt64) {
        self.maxReadLength = maxReadLength
        self.maxWriteLength = maxWriteLength
    }
}
