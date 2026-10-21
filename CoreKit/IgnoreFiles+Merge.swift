import Common
import Foundation

extension IgnoreFiles {
    /// A single branch through `names`, with `files` for the root and then
    /// each directory.
    init(branch names: [String], files: [[String: IgnoreFile]]) {
        precondition(files.count == names.count + 1)
        self.init(files: files[names.count])
        for (name, files) in zip(names, files).reversed() {
            self = IgnoreFiles(files: files, children: [name: self])
        }
    }

    var known: IgnoreFiles {
        IgnoreFiles(
            files: files.filter { $0.value != .remote },
            children: children.mapValues(\.known)
        )
    }

    var branch: [String]? {
        guard let child = children.first else { return [] }
        guard children.count == 1, let rest = child.value.branch else {
            return nil
        }
        return [child.key] + rest
    }

    /// Merges in what one side observed, and returns the paths of
    /// directories whose rules changed. The newer copy of each file wins, and
    /// a file left to the remote keeps what's known. A file missing remotely
    /// is dropped, but one missing locally is kept: it may not have arrived
    /// yet, and local deletes reach `IgnoreCache.remove` instead.
    mutating func merge(
        _ new: IgnoreFiles,
        from origin: IgnoreOrigin,
        at path: String = ""
    ) -> [String] {
        var merged = origin == .local ? files : [:]
        for (filename, file) in new.files {
            merged[filename] = Self.newer(file, than: files[filename])
        }
        var changed = merged == files ? [] : [path]
        files = merged

        for (name, child) in new.children {
            if children[name] == nil {
                children[name] = child.known
            } else {
                let childPath = path.isEmpty ? name : "\(path)/\(name)"
                changed += children[name]!.merge(
                    child,
                    from: origin,
                    at: childPath
                )
            }
        }
        return changed
    }

    mutating func remove(_ filename: String, in names: ArraySlice<String>) -> Bool {
        guard let name = names.first else {
            return files.removeValue(forKey: filename) != nil
        }
        return children[name]?.remove(filename, in: names.dropFirst()) ?? false
    }

    private static func newer(
        _ file: IgnoreFile,
        than known: IgnoreFile?
    ) -> IgnoreFile? {
        guard case .contents(_, let modified) = file else { return known }
        guard case .contents(_, let knownModified)? = known else { return file }
        return modified.seconds > knownModified.seconds ? file : known
    }
}

enum IgnoreOrigin: Equatable {
    case local
    case remote
}

extension Date {
    fileprivate var seconds: Int64 { Int64(timeIntervalSince1970.rounded(.down)) }
}
