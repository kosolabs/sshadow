public struct LogMessage: ExpressibleByStringInterpolation {
    public struct Segment: Message {
        let debug: String
        let display: String
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        public var segments: [Segment] = []

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ s: String) {
            append(debug: s, display: s)
        }

        public mutating func appendInterpolation(_ ref: Ref) {
            append(debug: ref.description, display: ref.display)
        }

        public mutating func appendInterpolation(
            _ v: some CustomStringConvertible
        ) {
            let s = String(describing: v)
            append(debug: s, display: s)
        }

        private mutating func append(debug: String, display: String) {
            segments.append(Segment(debug: debug, display: display))
        }
    }

    public let segments: [Segment]

    public init(stringLiteral v: String) {
        segments = [Segment(debug: v, display: v)]
    }

    public init(stringInterpolation i: StringInterpolation) {
        segments = i.segments
    }

    public var debug: String {
        segments.map { segment in segment.debug }.joined()
    }

    public var display: String {
        segments.map { segment in segment.display }.joined()
    }
}
