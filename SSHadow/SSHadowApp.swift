import SSHadowShared
import SwiftData
import SwiftUI

@main
struct SSHadowApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectionProfileListView()
        }
        .modelContainer(
            for: ConnectionProfile.self,
            inMemory: ProcessInfo.processInfo.arguments.contains("-uiTesting")
        )
    }
}
