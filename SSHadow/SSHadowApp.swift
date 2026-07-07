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

@MainActor
private class AppXPCService {
    static let shared = AppXPCService()

    let transfers = Transfers()
    private let listener: XPCListener?

    private init() {
        do {
            listener = try Agent.listener(transfers: transfers)
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

    private var transfers: Transfers {
        AppXPCService.shared.transfers
    }

    var body: some Scene {
        MenuBarExtra {
            RichMenuMainView()
        } label: {
            MenuBarIcon(isLoading: coordinator.isAnyBusy || !transfers.isEmpty)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)
        .environment(coordinator)
        .environment(transfers)

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
        .environment(coordinator)
        .environment(transfers)
    }
}
