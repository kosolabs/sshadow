import SwiftData
import SwiftUI

@main
struct SSHadowApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectionConfigListView()
        }
        .modelContainer(
            for: ConnectionConfig.self,
            inMemory: ProcessInfo.processInfo.arguments.contains("-uiTesting")
        )
    }
}
