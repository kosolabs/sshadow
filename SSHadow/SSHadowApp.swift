import Common
import SwiftData
import SwiftUI

private let logger = Logger(category: "SSHadowApp")

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
