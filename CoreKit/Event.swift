import Common
import Foundation

public struct Event: Message, Identifiable {
    public struct Source: Message {
        public let name: String
        public let url: String
    }

    public enum Level: String, Message, CaseIterable, Comparable {
        case info
        case notice
        case warning
        case error

        public var label: String {
            switch self {
            case .info: "INFO"
            case .notice: "NOTICE"
            case .warning: "WARNING"
            case .error: "ERROR"
            }
        }

        private var rank: Int {
            switch self {
            case .info: 0
            case .notice: 1
            case .warning: 2
            case .error: 3
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    public enum Category: String, Message, CaseIterable {
        case connection
        case sync
        case file
        case diagnostic

        public var label: String {
            switch self {
            case .connection: "Connection"
            case .sync: "Sync"
            case .file: "File"
            case .diagnostic: "Diagnostic"
            }
        }
    }

    public let id: UUID
    public let timestamp: Date
    public let source: Source?
    public let level: Level
    public let category: Category
    public let message: String
    public let detail: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        source: Source?,
        level: Level,
        category: Category,
        message: String,
        detail: String? = nil,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.category = category
        self.message = message
        self.detail = detail
    }

    public var logLine: String {
        var parts: [String] = []
        parts.append(timestamp.formatted(.iso8601))
        parts.append(level.label)
        if let source {
            parts.append(source.name)
            parts.append(source.url)
        }
        parts.append(message)
        if let detail {
            parts.append(detail)
        }
        return parts.joined(separator: "  ")
    }
}
