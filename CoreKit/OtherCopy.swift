import Foundation

func interferenceDetail(other: URL, own: URL, home: URL) -> String {
    let otherCopy =
        location(of: other, home: home).map { "The copy at \($0)" }
        ?? "A copy opened from Downloads or a disk image"
    let ownCopy = location(of: own, home: home).map { "this one at \($0)" } ?? "this one"
    return "\(otherCopy) is syncing this folder instead of \(ownCopy)."
}

extension URL {
    static let userHome = URL(
        filePath: String(cString: getpwuid(getuid()).pointee.pw_dir),
        directoryHint: .isDirectory
    )

    // .../SSHadow.app/Contents/PlugIns/Extension.appex
    var containingApp: URL {
        deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private func location(of app: URL, home: URL) -> String? {
    let path = displayPath(app)
    guard !path.contains("/AppTranslocation/") else { return nil }
    let homePath = displayPath(home)
    guard path.hasPrefix(homePath + "/") else { return path }
    return "~" + path.dropFirst(homePath.count)
}

private func displayPath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
}
