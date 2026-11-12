import Common
import CoreKit
import FileProvider
import SwiftData
import SwiftUI

private let logger = Logger(category: "SSHadowApp")

@MainActor
private func startup() {
    logger.notice(
        "Started "
            + "from \(Bundle.main.bundleURL.path(percentEncoded: false)) "
            + "(version \(SSHadow.version), build \(SSHadow.build))"
    )
    Events.shared.persist(in: SSHadowApp.modelContainer)
    Task {
        await reconnectEnabledDomains()
        await removeOrphanedDomains()
    }
}

@MainActor
private func reconnectEnabledDomains() async {
    let descriptor = FetchDescriptor<ConnectionConfigModel>(
        predicate: #Predicate { $0.enabled }
    )
    do {
        for profile in try SSHadowApp.modelContainer.mainContext.fetch(descriptor) {
            Task { await profile.reconnectOnLaunch() }
        }
    } catch {
        logger.error("Failed to load enabled connections: \(error)")
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
    @State private var connectionsNavigation = ConnectionsNavigation()

    init() {
        startup()
    }

    var body: some Scene {
        MenuBarExtra {
            RichMenuMainView()
                .modelContainer(Self.modelContainer)
                .environment(connectionsNavigation)
                .environment(Connections.shared)
                .environment(Transfers.shared)
                .environment(Events.shared)
        } label: {
            MenuBarIcon(
                isLoading: Events.shared.isActive || Transfers.shared.isActive
            )
            .modifier(OpensRequestedWindows())
        }
        .menuBarExtraStyle(.window)

        Window("Connections", id: "connections") {
            ConnectionsView()
                .modelContainer(Self.modelContainer)
                .environment(connectionsNavigation)
                .environment(activation)
                .environment(Connections.shared)
                .environment(Transfers.shared)
                .environment(Events.shared)
        }
        .handlesExternalEvents(matching: [])

        Settings {
            SettingsView()
                .modelContainer(Self.modelContainer)
                .environment(activation)
        }

        Window("Event Log", id: "events") {
            EventLogView()
                .modelContainer(Self.modelContainer)
                .environment(activation)
                .environment(Transfers.shared)
                .environment(Events.shared)
        }
        .handlesExternalEvents(matching: [])

        WindowGroup(
            "Can't Connect",
            id: "unreachable",
            for: UnreachableFix.self
        ) {
            $fix in
            if let fix {
                UnreachableView(fix: fix)
                    .environment(activation)
            }
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])

        Window("About SSHadow", id: "about") {
            AboutView()
                .environment(activation)
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])
    }
}
