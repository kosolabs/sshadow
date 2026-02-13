import OSLog

public func getLogger(category: String) -> Logger {
    return Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.kosolabs.SSHadow",
        category: category,
    )
}
