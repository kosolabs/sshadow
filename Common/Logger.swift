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
