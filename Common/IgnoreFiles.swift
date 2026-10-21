import Foundation

public enum IgnoreFile: Message, PrettyDescribable {
    case contents(String, modified: Date)
    case remote
}

public struct IgnoreFiles: Message, PrettyDescribable {
    public var files: [String: IgnoreFile]
    public var children: [String: IgnoreFiles]

    public init(
        files: [String: IgnoreFile] = [:],
        children: [String: IgnoreFiles] = [:]
    ) {
        self.files = files
        self.children = children
    }
}
