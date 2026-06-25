import AgentKit
import Common
import FileProvider
import SwiftData
import SwiftUI
import XPC

private let logger = Logger(category: "SSHadowApp")

private func reconnectAllDomains() {
    Task {
        let domains: [NSFileProviderDomain]
        do {
            domains = try await NSFileProviderManager.domains()
        } catch {
            logger.error("Failed to list domains: \(error)")
            return
        }
        for domain in domains {
            do {
                try await domain.manager.reconnect()
                logger.info("Reconnected \(domain)")
            } catch {
                logger.error("Failed to reconnect \(domain): \(error)")
            }
        }
    }
}

private class AppXPCService {
    static let shared = AppXPCService()

    private let listener: XPCListener?

    private init() {
        do {
            listener = try Agent.listener()
        } catch {
            listener = nil
            logger.error("Failed to create XPC listener: \(error)")
            return
        }
        logger.info("App XPC: listening on \(SSHadow.appServiceName)")

        reconnectAllDomains()
    }
}

@main
struct SSHadowApp: App {
    private let modelContainer: ModelContainer
    @State private var coordinator = ConnectionCoordinator()

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

    var menuIcon: String {
        if coordinator.isAnyBusy {
            return "externaldrive.badge.timemachine"
        }
        if coordinator.isAnyError {
            return "externaldrive.trianglebadge.exclamationmark"
        }
        return "externaldrive.badge.icloud"
    }

    var body: some Scene {
        MenuBarExtra("SSHadow", systemImage: menuIcon) {
            RichMenuMainView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)
        .environment(coordinator)

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
        .environment(coordinator)
    }
}
