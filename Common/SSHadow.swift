import Foundation

private func value(for key: String, fallback: String = "-") -> String {
    Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
}

public enum SSHadow {
    public static let bundleId =
        Bundle.main.bundleIdentifier ?? "com.kosolabs.SSHadow"
    public static let appGroup = "group.com.kosolabs.SSHadow"
    public static let appServiceName = "\(appGroup).App"
    public static let extensionServiceName = NSFileProviderServiceName(
        "\(appGroup).Extension"
    )
    public static let groupUrl = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroup
    )!
    public static let version = value(for: "CFBundleShortVersionString")
    public static let build = value(for: "CFBundleVersion")
}
