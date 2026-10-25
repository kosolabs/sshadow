import Common
import Foundation
import Ignore

private let logger = Logger(category: "IgnoreCache")

typealias FolderIgnoreFiles = (dir: String, files: [String: IgnoreFile])

struct IgnoreFileVersion: Equatable {
    let modifyTime: Date?
    let modifyTimeNanos: UInt32?
    let size: UInt64?
}

struct IgnoreCache {
    private var tree: IgnoreTree
    private var versions: [String: IgnoreFileVersion] = [:]

    init(filenames: [String]) {
        self.tree = IgnoreTree(filenames: filenames)
    }

    @discardableResult
    mutating func update(_ levels: [FolderIgnoreFiles]) -> [String] {
        var changed: [String] = []
        for (dir, files) in levels {
            let known = tree.knows(dir)
            let old = tree.files(in: dir) ?? [:]
            var texts: [String: String] = [:]
            for (filename, file) in files {
                switch file {
                case .contents(let text):
                    texts[filename] = text
                case .unresolved:
                    texts[filename] = old[filename]
                }
            }
            for filename in Set(old.keys).union(texts.keys)
            where old[filename] != texts[filename] {
                versions[subpath(filename, in: dir)] = nil
            }
            if tree.set(texts, in: dir), known {
                changed.append(dir)
            }
        }
        return changed
    }

    mutating func record(
        _ version: IgnoreFileVersion,
        of filename: String,
        in dir: String
    ) {
        versions[subpath(filename, in: dir)] = version
    }

    func isCurrent(
        _ filename: String,
        in dir: String,
        at version: IgnoreFileVersion
    ) -> Bool {
        versions[subpath(filename, in: dir)] == version
    }

    func knows(_ dir: String) -> Bool { tree.knows(dir) }

    func rule(
        ignoring name: String,
        in dir: String,
        isDirectory: Bool
    ) -> Rule? {
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
