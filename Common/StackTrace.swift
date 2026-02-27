import Foundation

public struct StackTrace: CustomStringConvertible {
    let file: String
    let line: Int
    private let _frames: [String]

    public static func capture(
        file: String = #fileID,
        line: Int = #line,
    ) -> StackTrace {
        return StackTrace(
            file: file,
            line: line,
            _frames: Thread.callStackSymbols
        )
    }

    public var source: String {
        "\(file):\(line)"
    }

    public var caller: String {
        guard _frames.indices.contains(2) else { return "Unknown" }
        let demangled = demangle(symbol: _frames[2])
        return cleanFunctionName(from: demangled)
    }
    
    public var origin: String {
        "\(caller) (\(source))"
    }

    public var frames: [String] {
        _frames.map { demangle(symbol: $0) }
    }

    public var description: String {
        "\(source)\n\(frames.joined(separator: "\n"))"
    }

    // MARK: - Private Helpers

    private func cleanFunctionName(from demangled: String) -> String {
        let parts = demangled.components(separatedBy: " ")
        if let functionPart = parts.first(where: {
            $0.contains(".") && $0.contains("(")
        }) {
            return functionPart.components(separatedBy: "(").first
                ?? functionPart
        }
        return demangled
    }

    private func demangle(symbol: String) -> String {
        let components = symbol.components(separatedBy: " ")
        guard
            let mangled = components.first(where: {
                $0.hasPrefix("$s") || $0.hasPrefix("_T")
            })
        else {
            return symbol
        }

        let result = _stdlib_demangle(mangled, mangled.count, nil, nil, 0)
        if let result = result {
            defer { free(result) }
            let demangledName = String(cString: result)
            return symbol.replacingOccurrences(of: mangled, with: demangledName)
        }
        return symbol
    }
}

@_silgen_name("swift_demangle")
private func _stdlib_demangle(
    _ mangledName: UnsafePointer<Int8>?,
    _ mangledNameLength: Int,
    _ outputBuffer: UnsafeMutablePointer<Int8>?,
    _ outputBufferLength: UnsafeMutablePointer<Int>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<Int8>?
