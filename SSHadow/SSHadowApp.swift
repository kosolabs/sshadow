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
            try await DomainRegistry.shared.connect(config: config)
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
    static let modelContainer = try! AppDB.getModelContainer(
        config: ModelConfiguration(
            isStoredInMemoryOnly: ProcessInfo.processInfo
                .arguments
                .contains("-uiTesting")
        )
    )

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var activation = WindowActivationTracker()

    init() {
        startup()
    }

    var body: some Scene {
        MenuBarExtra {
            RichMenuMainView()
        } label: {
            MenuBarIcon(
                isLoading: Events.shared.isActive || Transfers.shared.isActive
            )
        }
        .menuBarExtraStyle(.window)
        .modelContainer(Self.modelContainer)
        .environment(Connections.shared)
        .environment(Transfers.shared)
        .environment(Events.shared)

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .handlesExternalEvents(matching: [])
        .modelContainer(Self.modelContainer)
        .environment(activation)
        .environment(Connections.shared)
        .environment(Transfers.shared)
        .environment(Events.shared)

        Window("Event Log", id: "events") {
            EventLogView()
        }
        .handlesExternalEvents(matching: [])
        .environment(activation)
        .environment(Transfers.shared)
        .environment(Events.shared)

        Window("About SSHadow", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])
        .environment(activation)
    }
}
