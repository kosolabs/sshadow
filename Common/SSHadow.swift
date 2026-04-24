import Foundation

public enum SSHadow {
    public static let appGroup = "group.com.kosolabs.SSHadow"
    public static let bundleID =
        Bundle.main.bundleIdentifier ?? "com.kosolabs.SSHadow"
    public static let groupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroup
    )!
}
