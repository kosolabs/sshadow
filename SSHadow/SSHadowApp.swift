import AgentKit
import Common
import FileProvider
import SwiftData
import SwiftUI
import XPC

private let logger = Logger(category: "SSHadowApp")

private func reconnectAllDomains() {
    Task {
        for config in await AppDB.shared.enabledConfigs() {
            let domain = config.domain
            do {
                try await Agent.shared.register(config: config)
            } catch {
                logger.error("Failed to register \(domain): \(error)")
            }
            do {
                try await domain.manager.reconnect()
            } catch {
                logger.error("Failed to reconnect \(domain): \(error)")
            }
            do {
                try await DomainXPCBroker.shared.broker(domain)
            } catch {
                logger.error("Failed to broker \(domain): \(error)")
            }
            logger.info("Reconnected \(domain)")
        }
    }
}

@MainActor
private class AppXPCService {
    static let shared = AppXPCService()

    let transfers = Transfers()
    private let listener: XPCListener

    private init() {
        do {
            listener = try XPCListener(service: SSHadow.appServiceName) {
                request in
                Agent.shared.accept(request: request)
            }
        } catch {
            logger.fatal("Failed to create XPC listener: \(error)")
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

        Window("About SSHadow", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
