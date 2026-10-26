import Common
import Foundation

extension IgnoreSnapshot {
    static func read(
        _ filenames: [String],
        from root: URL,
        to directory: URL
    ) -> IgnoreSnapshot? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = directory.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return nil }

        var url = root
        var path = ""
        var folders = [IgnoreFolder.read(filenames, in: url, at: path)]
        for name in components.dropFirst(rootComponents.count) {
            url = url.appending(path: name, directoryHint: .isDirectory)
            path = path.isEmpty ? name : "\(path)/\(name)"
            folders.append(IgnoreFolder.read(filenames, in: url, at: path))
        }
        return folders
    }
}

extension IgnoreFolder {
    fileprivate static func read(
        _ filenames: [String],
        in url: URL,
        at path: String
    ) -> IgnoreFolder {
        IgnoreFolder(
            path: path,
            files: filenames.compactMap { IgnoreFile.read($0, in: url) }
        )
    }
}

extension IgnoreFile {
    fileprivate static func read(_ name: String, in dir: URL) -> IgnoreFile? {
        let url = dir.appending(path: name, directoryHint: .notDirectory)
        var st = stat()
        guard lstat(url.path(percentEncoded: false), &st) == 0 else {
            guard errno != ENOENT else { return nil }
            return IgnoreFile(name: name, content: .unresolved)
        }
        guard st.st_flags & UInt32(SF_DATALESS) == 0,
            let data = try? Data(contentsOf: url)
        else { return IgnoreFile(name: name, content: .unresolved) }
        return IgnoreFile(
            name: name,
            content: .loaded(
                String(decoding: data, as: UTF8.self),
                version: Version(st)
            )
        )
    }
}

extension IgnoreFile.Version {
    fileprivate init(_ st: stat) {
        self.init(
            modifyTime: Date(
                timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)
            ),
            size: UInt64(st.st_size)
        )
    }
}
