import Foundation

private let logger = Logger(category: "FileTree")

/// A snapshot of a local directory tree, used to upload packages.
///
/// The File Provider hands packages (`.app`, `.dSYM`, `.rtfd`, …) to the
/// extension as a single item whose contents are a directory, so the whole
/// tree has to be walked and recreated on the server.
public struct FileTree: Sendable {
    public struct Entry: Sendable {
        public enum Kind: Sendable {
            case file(size: UInt64)
            case folder
            case symlink(target: String)
        }

        /// The location of the entry on disk.
        public let url: URL

        /// The POSIX path of the containing directory, relative to the root of
        /// the tree. Empty for entries directly inside the root.
        public let parent: String

        public let kind: Kind
        public let flags: Item.Flags

        public var name: String { url.lastPathComponent }

        /// The POSIX path of the entry, relative to the root of the tree.
        public var path: String {
            parent.isEmpty ? name : "\(parent)/\(name)"
        }

        public var size: UInt64 {
            if case .file(let size) = kind { size } else { 0 }
        }

        public var isFolder: Bool {
            if case .folder = kind { true } else { false }
        }
    }

    public let root: URL

    /// The entries below the root, ordered so that a folder always precedes
    /// its children.
    public let entries: [Entry]

    public var totalSize: UInt64 {
        entries.reduce(0) { $0 + $1.size }
    }

    /// Walks `root`, recording symlinks as-is rather than following them.
    public init(root: URL) throws {
        self.root = root
        var entries: [Entry] = []
        try FileTree.walk(root, parent: "", into: &entries)
        self.entries = entries
    }

    private static func walk(
        _ url: URL,
        parent: String,
        into entries: inout [Entry]
    ) throws {
        let manager = FileManager.default
        let names = try manager.contentsOfDirectory(atPath: url.path)

        for name in names.sorted() {
            let child = url.appending(path: name)
            let attrs = try manager.attributes(of: child)
            let flags = Item.Flags(from: mode_t(attrs.filePosixPermissions()))
            let path = parent.isEmpty ? name : "\(parent)/\(name)"

            switch attrs.fileType() {
            case FileAttributeType.typeSymbolicLink.rawValue:
                entries.append(
                    Entry(
                        url: child,
                        parent: parent,
                        kind: .symlink(
                            target: try manager.destinationOfSymbolicLink(
                                at: child
                            )
                        ),
                        flags: flags
                    )
                )
            case FileAttributeType.typeDirectory.rawValue:
                entries.append(
                    Entry(
                        url: child,
                        parent: parent,
                        kind: .folder,
                        flags: flags
                    )
                )
                try walk(child, parent: path, into: &entries)
            case FileAttributeType.typeRegular.rawValue:
                entries.append(
                    Entry(
                        url: child,
                        parent: parent,
                        kind: .file(size: attrs.fileSize()),
                        flags: flags
                    )
                )
            default:
                logger.info(
                    "Skipping \(path): unsupported type \(attrs.fileType() ?? "unknown")"
                )
            }
        }
    }

    /// The names expected in each directory of the tree, keyed by the
    /// directory's path relative to the root.
    public var expectedNames: [String: Set<String>] {
        var result: [String: Set<String>] = ["": []]
        for entry in entries where entry.isFolder {
            result[entry.path] = []
        }
        for entry in entries {
            result[entry.parent, default: []].insert(entry.name)
        }
        return result
    }
}
