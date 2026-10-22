import Common
import Foundation

extension IgnoreFiles {
    static func read(
        _ filenames: [String],
        from root: URL,
        to directory: URL
    ) -> IgnoreFiles? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = directory.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return nil }

        let names = Array(components.dropFirst(rootComponents.count))
        var urls = [root]
        for name in names {
            urls.append(
                urls[urls.count - 1].appending(
                    path: name,
                    directoryHint: .isDirectory
                )
            )
        }

        var branch = IgnoreFiles(
            files: read(filenames, in: urls[urls.count - 1])
        )
        for (name, url) in zip(names, urls).reversed() {
            branch = IgnoreFiles(
                files: read(filenames, in: url),
                children: [name: branch]
            )
        }
        return branch
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
                if errno != ENOENT { files[filename] = .remote }
                continue
            }
            if st.st_flags & UInt32(SF_DATALESS) != 0 {
                files[filename] = .remote
            } else if let data = try? Data(contentsOf: url) {
                files[filename] = .contents(
                    String(decoding: data, as: UTF8.self)
                )
            } else {
                files[filename] = .remote
            }
        }
        return files
    }
}
