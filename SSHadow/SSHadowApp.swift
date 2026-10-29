import Common
import CoreKit
import FileProvider
import SwiftData
import SwiftUI

private let logger = Logger(category: "SSHadowApp")

private func startup() {
    Task {
        await reconnectEnabledDomains()
        await removeOrphanedDomains()
    }
}

private func reconnectEnabledDomains() async {
    for config in await AppDB.shared.enabledConfigs() {
        do {
            try await DomainRegistry.shared.reconnect(config: config)
        } catch {
            logger.error("Failed to enable \(config.domain): \(error)")
        }
    }
}

private func removeOrphanedDomains() async {
    guard let enabledIds = await AppDB.shared.enabledIds() else {
        logger.error("Failed to clean up orphaned domains")
        return
    }
    await DomainRegistry.shared.removeOrphanedDomains(enabledIds: enabledIds)
}

@main
struct SSHadowApp: App {
    static let modelContainer = try! AppDB.getModelContainer()

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var activation = WindowActivationTracker()
    @State private var settingsNavigation = SettingsNavigation()

    init() {
        startup()
    }

    var body: some Scene {
        MenuBarExtra {
            RichMenuMainView()
                .modelContainer(Self.modelContainer)
                .environment(settingsNavigation)
                .environment(Connections.shared)
                .environment(Transfers.shared)
                .environment(Events.shared)
        } label: {
            MenuBarIcon(
                isLoading: Events.shared.isActive || Transfers.shared.isActive
            )
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .modelContainer(Self.modelContainer)
                .environment(settingsNavigation)
                .environment(activation)
                .environment(Connections.shared)
                .environment(Transfers.shared)
                .environment(Events.shared)
        }
        .handlesExternalEvents(matching: [])

        Window("Event Log", id: "events") {
            EventLogView()
                .environment(activation)
                .environment(Transfers.shared)
                .environment(Events.shared)
        }
        .handlesExternalEvents(matching: [])

        Window("About SSHadow", id: "about") {
            AboutView()
                .environment(activation)
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])
    }
}
