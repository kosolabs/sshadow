import AgentKit
import Common
import SwiftData
import SwiftUI
import XPC

private let logger = Logger(category: "SSHadowApp")

private class AppXPCService {
    static let shared = AppXPCService()

    private let listener: XPCListener?

    private init() {
        do {
            listener = try Agent.create()
        } catch {
            listener = nil
            logger.error("Failed to create XPC listener: \(error)")
            return
        }
        logger.info("App XPC: listening on \(SSHadow.appServiceName)")
    }
}

@main
struct SSHadowApp: App {
    init() {
        _ = AppXPCService.shared
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
