import Common
import Foundation

private let lsregister =
    "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
    + "LaunchServices.framework/Support/lsregister"

public struct InterferenceFix: Equatable, Sendable {
    public let otherCopy: String
    public let otherApp: URL?
    public let command: String

    public init(otherExtension: URL, home: URL) {
        let app = URL(filePath: displayPath(otherExtension.containingApp))
        let appex = URL(filePath: displayPath(otherExtension))
        self.otherCopy = description(of: app, home: home)
        self.otherApp = location(of: app, home: home) == nil ? nil : app
        self.command = """
            pluginkit -r \(appex.shellEscapedPath)
            \(lsregister) -u \(app.shellEscapedPath)
            killall fileproviderd
            """
    }
}

func interferenceDetail(other: URL, own: URL, home: URL) -> String {
    let ownCopy = location(of: own, home: home).map { "this one at \($0)" } ?? "this one"
    return "\(description(of: other, home: home)) is syncing this folder instead of \(ownCopy)."
}

extension URL {
    public static let userHome = URL(
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

private func description(of app: URL, home: URL) -> String {
    location(of: app, home: home).map { "The copy at \($0)" }
        ?? "A copy opened from Downloads or a disk image"
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
