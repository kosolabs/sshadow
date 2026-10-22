import Common
import Ignore

struct IgnoreCache {
    private var tree: IgnoreTree

    init(filenames: [String]) {
        self.tree = IgnoreTree(filenames: filenames)
    }

    @discardableResult
    mutating func update(_ ignoreFiles: IgnoreFiles) -> [String] {
        var changed: [String] = []
        for (dir, files) in ignoreFiles.levels {
            let known = tree.knows(dir)
            var texts: [String: String] = [:]
            for (filename, file) in files {
                switch file {
                case .contents(let text): texts[filename] = text
                case .remote: texts[filename] = tree.files(in: dir)?[filename]
                }
            }
            if tree.set(texts, in: dir), known {
                changed.append(dir)
            }
        }
        return changed
    }

    func knows(_ dir: String) -> Bool { tree.knows(dir) }

    func rule(ignoring name: String, in dir: String, isDirectory: Bool) -> Rule? {
        let path = dir.isEmpty ? name : "\(dir)/\(name)"
        guard case .ignored(let rule)? = tree.matched(path, isDirectory: isDirectory)
        else { return nil }
        return rule
    }
}
