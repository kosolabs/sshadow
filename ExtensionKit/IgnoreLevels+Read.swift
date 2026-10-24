import Common
import Foundation

extension IgnoreLevels {
    static func read(
        _ filenames: [String],
        from root: URL,
        to directory: URL
    ) -> IgnoreLevels? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = directory.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return nil }

        var dir = root
        var levels = [read(filenames, in: dir)]
        for name in components.dropFirst(rootComponents.count) {
            dir = dir.appending(path: name, directoryHint: .isDirectory)
            levels.append(read(filenames, in: dir))
        }
        return levels
    }

    private static func read(
        _ filenames: [String],
        in dir: URL
    ) -> [String: IgnoreFile] {
        var files: [String: IgnoreFile] = [:]
        for filename in filenames {
            let url = dir.appending(
                path: filename,
                directoryHint: .notDirectory
            )
            var st = stat()
            guard lstat(url.path(percentEncoded: false), &st) == 0 else {
                if errno != ENOENT { files[filename] = .unresolved }
                continue
            }
            if st.st_flags & UInt32(SF_DATALESS) != 0 {
                files[filename] = .unresolved
            } else if let data = try? Data(contentsOf: url) {
                files[filename] = .contents(
                    String(decoding: data, as: UTF8.self)
                )
            } else {
                files[filename] = .unresolved
            }
        }
        return files
    }
}
