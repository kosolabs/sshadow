import Common
import Foundation

public struct Event: Message, Identifiable {
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
    public let connectionId: UUID
    public let level: Level
    public let category: Category
    public let message: String
    public let detail: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        connectionId: UUID,
        level: Level,
        category: Category,
        message: String,
        detail: String? = nil,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.connectionId = connectionId
        self.level = level
        self.category = category
        self.message = message
        self.detail = detail
    }

    public var logLine: String {
        let time = timestamp.formatted(.iso8601)
        let suffix = detail.map { " — \($0)" } ?? ""
        return "\(time)  \(level.label)  \(message)\(suffix)"
    }
}
