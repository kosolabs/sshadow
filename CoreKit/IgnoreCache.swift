import Common
import IgnoreModule

struct IgnoreCache {
    private let filenames: [String]
    private var root: IgnoreFiles?
    private var changes: [String: (origin: IgnoreOrigin, order: Int)] = [:]
    private var changeCount = 0

    init(filenames: [String]) {
        self.filenames = filenames
    }

    @discardableResult
    mutating func update(
        _ ignoreFiles: IgnoreFiles,
        from origin: IgnoreOrigin
    ) -> [String] {
        guard root != nil else {
            root = ignoreFiles.known
            return []
        }
        let changed = root!.merge(ignoreFiles, from: origin)
        record(changed, from: origin)
        return changed
    }

    /// Forgets `filename` in `dir` after it was deleted or moved locally.
    @discardableResult
    mutating func remove(_ filename: String, in dir: String) -> Bool {
        let names = dir.split(separator: "/").map(String.init)
        guard root?.remove(filename, in: names[...]) == true else { return false }
        record([dir], from: .local)
        return true
    }

    /// Where the most recent change to the rules that apply in `dir` came from.
    func lastChange(affecting dir: String) -> IgnoreOrigin? {
        var path = ""
        var last = changes[path]
        for name in dir.split(separator: "/") {
            path = path.isEmpty ? String(name) : "\(path)/\(name)"
            if let change = changes[path], change.order > last?.order ?? 0 {
                last = change
            }
        }
        return last?.origin
    }

    func knows(_ dir: String) -> Bool {
        node(at: dir) != nil
    }

    func rule(
        ignoring name: String,
        in dir: String,
        isDirectory: Bool
    ) -> Glob? {
        var parent = ""
        for component in dir.split(separator: "/").map(String.init) {
            if let glob = matched(component, in: parent, isDirectory: true) {
                return glob
            }
            parent = parent.isEmpty ? component : "\(parent)/\(component)"
        }
        return matched(name, in: dir, isDirectory: isDirectory)
    }

    private func matched(
        _ name: String,
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
            if case .contents(let text, _) = file { text } else { nil }
        }
    }

    private mutating func record(_ dirs: [String], from origin: IgnoreOrigin) {
        for dir in dirs {
            changeCount += 1
            changes[dir] = (origin, changeCount)
        }
    }
}
