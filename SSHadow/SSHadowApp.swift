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
    private let modelContainer: ModelContainer

    @State private var isBusy = false

    init() {
        _ = AppXPCService.shared
        modelContainer = try! AppDB.getModelContainer(
            config: ModelConfiguration(
                isStoredInMemoryOnly: ProcessInfo.processInfo
                    .arguments
                    .contains("-uiTesting")
            )
        )
    }

    var body: some Scene {
        MenuBarExtra(
            "SSHadow",
            systemImage: isBusy
                ? "externaldrive.badge.timemachine"
                : "externaldrive.badge.icloud"
        ) {
            MainMenuView(isBusy: $isBusy).modelContainer(modelContainer)
        }

        Window("SSHadow Settings", id: "settings") {
            ConnectionProfileListView()
        }
        .modelContainer(modelContainer)
    }
}
