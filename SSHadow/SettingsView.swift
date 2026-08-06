import CoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(WindowActivationTracker.self) private var activation

    @State private var section: SidebarSection? = .connections
    @State private var selectedConfig: ConnectionConfigModel?

    var body: some View {
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
                ConnectionConfigListView(selection: $selectedConfig)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            case nil:
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "gearshape"
                )
            }
        } detail: {
            if let selectedConfig {
                ConnectionConfigEditView(config: selectedConfig)
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
    }
}

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
