import Foundation
import os

private typealias OSLogger = os.Logger

public struct Logger: Sendable {
    private let logger: OSLogger

    public init(
        subsystem: String? = Bundle.main.bundleIdentifier,
        category: String
    ) {
        self.logger = OSLogger(
            subsystem: subsystem ?? "com.kosolabs.SSHadow",
            category: category
        )
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    public func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
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

private func demangle(symbol: String) -> String {
    // Extract the mangled part of the string (usually between $ and space)
    let components = symbol.components(separatedBy: " ")
    guard let mangledName = components.first(where: { $0.contains("$") }) else {
        return symbol
    }

    let result = _stdlib_demangle(mangledName, mangledName.count, nil, nil, 0)
    if let result = result {
        let demangled = String(cString: result)
        free(result)
        return demangled
    }
    return symbol
}
