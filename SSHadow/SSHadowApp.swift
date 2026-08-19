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
                try await DomainRegistry.shared.connect(config: config)
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
            MenuBarIcon(isLoading: !Transfers.shared.isEmpty)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)
        .environment(Connections.shared)
        .environment(Transfers.shared)

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .modelContainer(modelContainer)
        .environment(activation)
        .environment(Connections.shared)
        .environment(Transfers.shared)

        Window("About SSHadow", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .environment(activation)
    }
}
