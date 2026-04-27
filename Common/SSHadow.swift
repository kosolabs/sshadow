import Foundation

public enum SSHadow {
    public static let bundleId =
        Bundle.main.bundleIdentifier ?? "com.kosolabs.SSHadow"
    public static let appGroup = "group.com.kosolabs.SSHadow"
    public static let agentServiceName = "\(appGroup).Agent"
    public static let groupUrl = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroup
    )!
}
