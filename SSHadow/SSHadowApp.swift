import Common
import ServiceManagement
import SwiftData
import SwiftUI

private let logger = Logger(category: "SSHadowApp")

@main
struct SSHadowApp: App {
    init() {
        let agent = SMAppService.agent(
            plistName: "\(SSHadow.agentServiceName).plist"
        )
        try? agent.unregister()
        do {
            try agent.register()
        } catch {
            logger.error("Failed to register agent: \(error)")
        }
    }

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
