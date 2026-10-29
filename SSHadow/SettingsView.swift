import CoreKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(WindowActivationTracker.self) private var activation
    @Query private var configs: [ConnectionConfigModel]

    @State private var section: SidebarSection? = .connections

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView {
            List(selection: $section) {
                ForEach(SidebarSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } content: {
            switch section {
            case .connections:
                ConnectionConfigListView(selection: $navigation.selectedConfig)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            case nil:
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "gearshape"
                )
            }
        } detail: {
            if let selectedConfig = navigation.selectedConfig {
                ConnectionConfigEditView(config: selectedConfig)
            } else if configs.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No Connections",
                        systemImage: SidebarSection.connections.systemImage
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
        .frame(minWidth: 720, minHeight: 600)
        .onAppear { activation.retain() }
        .onDisappear { activation.release() }
    }}

enum SidebarSection: String, CaseIterable, Identifiable {
    case connections

    var id: Self { self }

    var title: String {
        switch self {
        case .connections: "Connections"
        }
    }

    var systemImage: String {
        switch self {
        case .connections: "externaldrive.badge.icloud"
        }
    }
}
