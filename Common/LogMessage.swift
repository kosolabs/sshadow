public struct LogMessage: ExpressibleByStringInterpolation {
    final public class StringInterpolation: StringInterpolationProtocol {
        var debug = ""
        var display = ""

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public func appendLiteral(_ s: String) {
            debug += s
            display += s
        }

        public func appendInterpolation(_ ref: Ref) {
            debug += ref.description
            display += ref.display
        }

        public func appendInterpolation(_ v: some CustomStringConvertible) {
            let s = String(describing: v)
            debug += s
            display += s
        }
    }

    public let debug: String
    public let display: String

    public init(stringLiteral v: String) {
        debug = v
        display = v
    }

    public init(stringInterpolation i: StringInterpolation) {
        debug = i.debug
        display = i.display
    }
}
