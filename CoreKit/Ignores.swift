import Common
import Ignore

private let logger = Logger(category: "Ignores")

struct Ignores {
    private var tree: IgnoreTree
    private var versions: [String: IgnoreFile.Version] = [:]

    func knows(_ dir: String) -> Bool {
        tree.knows(dir)
    }

    init(filenames: [String]) {
        self.tree = IgnoreTree(filenames: filenames)
    }

    @discardableResult
    mutating func update(_ snapshot: IgnoreSnapshot) -> [String] {
        var changed: [String] = []
        for folder in snapshot {
            let known = tree.knows(folder.path)
            let old = tree.files(in: folder.path) ?? [:]
            var texts: [String: String] = [:]
            for file in folder.files {
                switch file.content {
                case .loaded(let text, let version):
                    texts[file.name] = text
                    versions[subpath(file.name, in: folder.path)] = version
                case .unresolved:
                    texts[file.name] = old[file.name]
                }
            }
            for name in old.keys where texts[name] == nil {
                versions[subpath(name, in: folder.path)] = nil
            }
            if tree.set(texts, in: folder.path), known {
                changed.append(folder.path)
            }
        }
        return changed
    }

    func isCurrent(
        _ filename: String,
        in dir: String,
        at version: IgnoreFile.Version
    ) -> Bool {
        versions[subpath(filename, in: dir)] == version
    }

    func rule(
        ignoring name: String,
        in dir: String,
        isDirectory: Bool
    ) -> Rule? {
        guard knows(dir) else { return nil }
        let path = subpath(name, in: dir)
        guard let match = tree.matched(path, isDirectory: isDirectory) else {
            logger.fault("Ignore rules not loaded for \(path)")
            return nil
        }
        guard case .ignored(let rule) = match else { return nil }
        return rule
    }
}

extension Rule {
    var source: String { "\(file ?? "global"): \(original)" }
}

func subpath(_ name: String, in dir: String) -> String {
    dir.isEmpty ? name : "\(dir)/\(name)"
}

func ancestors(of dir: String) -> [String] {
    let names = dir.split(separator: "/")
    return names.indices.map { names[..<$0].joined(separator: "/") }
}
