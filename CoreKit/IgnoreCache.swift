import Common
import IgnoreModule

struct IgnoreCache {
    private let filenames: [String]
    private var root: IgnoreFiles?

    init(filenames: [String]) {
        self.filenames = filenames
    }

    @discardableResult
    mutating func update(_ ignoreFiles: IgnoreFiles) -> [String] {
        guard root != nil else {
            root = ignoreFiles.known
            return []
        }
        return root!.merge(ignoreFiles)
    }

    func knows(_ dir: String) -> Bool {
        node(at: dir) != nil
    }

    func rule(
        ignoring name: String,
        in dir: String,
        isDirectory: Bool
    ) -> Glob? {
        guard
            case .ignore(let glob) = ignore(for: dir)?.matched(
                name,
                isDir: isDirectory
            )
        else { return nil }
        return glob
    }

    private func node(at dir: String) -> IgnoreFiles? {
        var node = root
        for name in dir.split(separator: "/").map(String.init) {
            node = node?.children[name]
        }
        return node
    }

    private func ignore(for dir: String) -> Ignore? {
        guard var node = root else { return nil }
        var ignore = Ignore(
            filenames: filenames,
            files: Self.contents(of: node)
        )
        for name in dir.split(separator: "/").map(String.init) {
            guard let child = node.children[name] else { return nil }
            node = child
            ignore = ignore.child(name, files: Self.contents(of: node))
        }
        return ignore
    }

    private static func contents(of node: IgnoreFiles) -> [String: String] {
        node.files.compactMapValues { file in
            if case .contents(let text) = file { text } else { nil }
        }
    }
}
