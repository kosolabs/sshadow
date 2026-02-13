import Common
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "SSHadowApp"
)

@main
struct SSHadowApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectionProfileListView()
        }
        .modelContainer(
            for: ConnectionProfile.self,
            inMemory: isUITesting
        )
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
}
