import Common
import CoreKit
import SwiftData
import SwiftUI

private let logger = Logger(category: "SettingsView")

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(WindowActivationTracker.self) private var activation
    @Query private var configs: [ConnectionConfigModel]
    @Query private var storedSettings: [SettingsModel]

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView {
            List(selection: $navigation.section) {
                ForEach(SettingsSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch navigation.section {
            case .general:
                if let settings = storedSettings.first {
                    GeneralSettingsView(settings: settings)
                }
            case .connections:
                HSplitView {
                    ConnectionConfigListView(
                        selection: $navigation.selectedConfig
                    )
                    .frame(
                        minWidth: 250,
                        idealWidth: 300,
                        maxWidth: 400,
                        maxHeight: .infinity
                    )
                    connectionDetail
                        .frame(
                            minWidth: 300,
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                }
            case .advanced:
                if let settings = storedSettings.first {
                    AdvancedSettingsView(settings: settings)
                }
            case nil:
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "gearshape"
                )
            }
        }
        .frame(minWidth: 720, minHeight: 600)
        .onAppear {
            activation.retain()
            insertSettingsIfMissing()
        }
        .onDisappear { activation.release() }
        .onChange(of: storedSettings.first?.effectivePoll) {
            submitLiveSettings()
        }
        .onChange(of: storedSettings.first?.effectiveIgnoreFilenames) {
            submitLiveSettings()
        }
    }

    @ViewBuilder
    private var connectionDetail: some View {
        if let selectedConfig = navigation.selectedConfig {
            ConnectionConfigEditView(config: selectedConfig)
                .id(selectedConfig.id)
        } else if configs.isEmpty {
            ContentUnavailableView {
                Label(
                    "No Connections",
                    systemImage: SettingsSection.connections.systemImage
                )
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

    private func submitLiveSettings() {
        guard let settings = storedSettings.first else { return }
        for config in configs {
            config.submitLiveSettings(settings: settings)
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
