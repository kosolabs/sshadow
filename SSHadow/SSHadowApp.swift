import Common
import CoreKit
import FileProvider
import SwiftData
import SwiftUI

private let logger = Logger(category: "SSHadowApp")

private func reconnectAllDomains() {
    Task {
        for config in await AppDB.shared.enabledConfigs() {
            do {
                try await DomainRegistry.shared.enable(config: config)
            } catch {
                logger.error("Failed to enable \(config.domain): \(error)")
            }
        }
    }
}

@main
struct SSHadowApp: App {
    private let modelContainer: ModelContainer
    @State private var activation = WindowActivationTracker()
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

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .modelContainer(modelContainer)
        .environment(activation)
        .environment(coordinator)
        .environment(Transfers.shared)

        Window("About SSHadow", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .environment(activation)
    }
}
