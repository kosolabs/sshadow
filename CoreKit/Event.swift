import Common
import Foundation

public struct Event: Message, Identifiable {
    public enum Operation: Message, CustomStringConvertible {
        case setAttributes(
            path: String,
            flags: Item.Flags?,
            accessTime: Date?,
            modifyTime: Date?
        )
        case createSymlink(
            path: String,
            target: String
        )
        case createDirectory(
            path: String
        )
        case move(
            from: String,
            to: String
        )
        case remove(
            path: String,
            kind: Item.Kind
        )
        case upload(
            path: String
        )
        case download(
            path: String
        )

        public var description: String {
            switch self {
            case .setAttributes(
                let path,
                let flags,
                let accessTime,
                let modifyTime
            ):
                var changes: [String] = []
                if let flags { changes.append("permissions: \(flags)") }
                if let accessTime {
                    changes.append("accessTime: \(accessTime)")
                }
                if let modifyTime {
                    changes.append("modifyTime: \(modifyTime)")
                }
                return
                    "set attributes of \(path) to \(changes.joined(separator: ", "))"
            case .createSymlink(let path, let target):
                return "create symlink from \(path) to \(target)"
            case .createDirectory(let path):
                return "create directory at \(path)"
            case .move(let from, let to):
                return "move \(from) to \(to)"
            case .remove(let path, let kind):
                return "remove \(kind) \(path)"
            case .upload(let path):
                return "upload \(path)"
            case .download(let path):
                return "download \(path)"
            }
        }
    }

    public enum Outcome: Message, PrettyDescribable {
        case succeeded(detail: String? = nil)
        case failed(reason: String)
        case cancelled
    }

    public let id: UUID
    public let timestamp: Date
    public let operation: Operation
    public let outcome: Outcome

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        operation: Operation,
        outcome: Outcome
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operation = operation
        self.outcome = outcome
    }

    public var logLine: String {
        let time = timestamp.formatted(.iso8601)
        let status: String
        let detail: String?
        switch outcome {
        case .succeeded(let value):
            status = "OK"
            detail = value
        case .failed(let reason):
            status = "FAILED"
            detail = reason
        case .cancelled:
            status = "CANCELLED"
            detail = nil
        }
        let suffix = detail.map { " — \($0)" } ?? ""
        return "\(time)  \(status)  \(operation)\(suffix)"
    }
}
