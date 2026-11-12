import Common
import CoreKit
import SwiftData
import SwiftUI

private let logger = Logger(category: "ConnectionsView")

struct ConnectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectionsNavigation.self) private var navigation
    @Environment(WindowActivationTracker.self) private var activation
    @Query private var configs: [ConnectionConfigModel]

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView {
            ConnectionConfigListView(selection: $navigation.selectedConfig)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 600)
        .onAppear {
            activation.retain()
            insertSettingsIfMissing()
        }
        .onDisappear { activation.release() }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedConfig = navigation.selectedConfig {
            ConnectionConfigEditView(config: selectedConfig)
                .id(selectedConfig.id)
        } else if configs.isEmpty {
            ContentUnavailableView {
                Label("No Connections", systemImage: "externaldrive.badge.icloud")
            } description: {
                Text("Mount a remote directory over SSH in Finder.")
            } actions: {
                Button("Add Connection") {
                    navigation.addConnection(to: modelContext)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } else {
            ContentUnavailableView(
                "Select a Connection",
                systemImage: "globe"
            )
        }
    }

    private func insertSettingsIfMissing() {
        do {
            _ = try modelContext.settings()
        } catch {
            logger.error("Failed to load settings: \(error)")
        }
    }
}
