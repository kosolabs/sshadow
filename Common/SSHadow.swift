import Foundation

public enum SSHadow {
    public static let appGroup = "group.com.kosolabs.SSHadow"
    public static let bundleID =
        Bundle.main.bundleIdentifier ?? "com.kosolabs.SSHadow"

    public static func groupURL() throws -> URL {
        guard
            let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup
            )
        else {
            throw CocoaError(.fileReadUnknown)
        }
        return url
    }
}
