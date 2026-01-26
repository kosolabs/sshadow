import SwiftUI
import SwiftData

@main
struct SSHadowApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectionConfigListView()
        }
        .modelContainer(for: ConnectionConfig.self)
    }
}
