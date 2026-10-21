import Common
import Foundation
import Ignore

struct IgnoreCache {
    private var tree: IgnoreTree
    private var modified: [String: [String: Date]] = [:]
    private var changes: [String: (origin: IgnoreOrigin, order: Int)] = [:]
    private var changeCount = 0

    init(filenames: [String]) {
        self.tree = IgnoreTree(filenames: filenames)
    }

    /// Merges in what one side observed, and returns the directories whose
    /// rules changed. The newer copy of each file wins, and a file left to the
    /// remote keeps what's known. A file missing remotely is dropped, but one
    /// missing locally is kept: it may not have arrived yet, and local deletes
    /// reach `remove` instead.
    @discardableResult
    mutating func update(
        _ ignoreFiles: IgnoreFiles,
        from origin: IgnoreOrigin
    ) -> [String] {
        var changed: [String] = []
        for (dir, files) in ignoreFiles.levels {
            let known = tree.knows(dir)
            if merge(files, in: dir, from: origin), known {
                changed.append(dir)
            }
        }
        record(changed, from: origin)
        return changed
    }

    /// Forgets `filename` in `dir` after it was deleted or moved locally.
    @discardableResult
    mutating func remove(_ filename: String, in dir: String) -> Bool {
        guard tree.remove(filename, in: dir) else { return false }
        modified[dir]?[filename] = nil
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
        tree.knows(dir)
    }

    func rule(
        ignoring name: String,
        in dir: String,
        isDirectory: Bool
    ) -> Rule? {
        let path = dir.isEmpty ? name : "\(dir)/\(name)"
        guard
            case .ignored(let rule)? = tree.matched(
                path,
                isDirectory: isDirectory
            )
        else { return nil }
        return rule
    }

    private mutating func merge(
        _ files: [String: IgnoreFile],
        in dir: String,
        from origin: IgnoreOrigin
    ) -> Bool {
        let known = tree.files(in: dir) ?? [:]
        let knownDates = modified[dir] ?? [:]
        var texts = origin == .local ? known : [:]
        var dates = origin == .local ? knownDates : [:]
        for (filename, file) in files {
            guard case .contents(let text, let date) = file,
                known[filename] == nil
                    || date.seconds > knownDates[filename]?.seconds ?? .min
            else {
                texts[filename] = known[filename]
                dates[filename] = knownDates[filename]
                continue
            }
            texts[filename] = text
            dates[filename] = date
        }
        modified[dir] = dates
        return tree.set(texts, in: dir)
    }

    private mutating func record(_ dirs: [String], from origin: IgnoreOrigin) {
        for dir in dirs {
            changeCount += 1
            changes[dir] = (origin, changeCount)
        }
    }
}

enum IgnoreOrigin: Equatable {
    case local
    case remote
}

extension Date {
    fileprivate var seconds: Int64 { Int64(timeIntervalSince1970.rounded(.down)) }
}
