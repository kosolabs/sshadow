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
            try! AppDB.getModelContainer(
                config: ModelConfiguration(
                    isStoredInMemoryOnly: ProcessInfo.processInfo.arguments
                        .contains("-uiTesting")
                )
            )
        )
    }
}
