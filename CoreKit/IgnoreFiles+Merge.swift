import Common

extension IgnoreFiles {
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

    mutating func merge(
        _ new: IgnoreFiles,
        at path: String = ""
    ) -> [String] {
        var merged: [String: IgnoreFile] = [:]
        for (filename, file) in new.files {
            merged[filename] = file == .remote ? files[filename] : file
        }
        var changed = merged == files ? [] : [path]
        files = merged

        for (name, child) in new.children {
            if children[name] == nil {
                children[name] = child.known
            } else {
                let childPath = path.isEmpty ? name : "\(path)/\(name)"
                changed += children[name]!.merge(child, at: childPath)
            }
        }
        return changed
    }
}
