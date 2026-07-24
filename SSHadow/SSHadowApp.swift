import Common
import CoreKit
import FileProvider
import SwiftData
import SwiftUI

private let logger = Logger(category: "SSHadowApp")

private func reconnectAllDomains() {
    Task {
        for config in await AppDB.shared.enabledConfigs() {
            let domain = config.domain
            do {
                try await CoreService.shared.register(config: config)
                try await DomainXPCBroker.shared.broker(domain)
            } catch {
                logger.error("Failed to resume sync \(domain): \(error)")
            }
        }
    }
}

@main
struct SSHadowApp: App {
    private let modelContainer: ModelContainer
    @State private var coordinator = ConnectionCoordinator()

    init() {
        reconnectAllDomains()
        modelContainer = try! AppDB.getModelContainer(
            config: ModelConfiguration(
                isStoredInMemoryOnly: ProcessInfo.processInfo
                    .arguments
                    .contains("-uiTesting")
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            RichMenuMainView()
        } label: {
            MenuBarIcon(
                isLoading: coordinator.isAnyBusy || !Transfers.shared.isEmpty
            )
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)
        .environment(coordinator)
        .environment(Transfers.shared)

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
        .environment(coordinator)
        .environment(Transfers.shared)

        Window("About SSHadow", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
