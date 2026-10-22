import Common

extension IgnoreFiles {
    init(branch names: [String], files: [[String: IgnoreFile]]) {
        precondition(files.count == names.count + 1)
        self.init(files: files[names.count])
        for (name, files) in zip(names, files).reversed() {
            self = IgnoreFiles(files: files, children: [name: self])
        }
    }

    var branch: [String]? {
        guard let child = children.first else { return [] }
        guard children.count == 1, let rest = child.value.branch else {
            return nil
        }
        return [child.key] + rest
    }

    var levels: [(dir: String, files: [String: IgnoreFile])] {
        levels(at: "")
    }

    private func levels(at path: String) -> [(dir: String, files: [String: IgnoreFile])] {
        var levels = [(path, files)]
        for (name, child) in children {
            levels += child.levels(at: path.isEmpty ? name : "\(path)/\(name)")
        }
        return levels
    }
}
