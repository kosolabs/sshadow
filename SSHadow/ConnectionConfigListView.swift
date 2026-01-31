import Foundation
import SwiftData
import SwiftUI

struct ConnectionConfigListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConnectionConfig.host) private var configs: [ConnectionConfig]

    @State private var selection: ConnectionConfig?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(configs) { config in
                    NavigationLink(value: config) {
                        HStack {
                            Image(
                                systemName:
                                    "externaldrive.connected.to.line.below"
                            )
                            .font(.system(size: 18))
                            .foregroundColor(
                                config.isEnabled() ? .green : .secondary
                            )
                            VStack(alignment: .leading) {
                                if let name = config.name {
                                    Text(name)
                                    Text(config.url ?? "New Connection")
                                        .font(.caption)
                                } else {
                                    Text(config.url ?? "New Connection")
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier(
                        "connectionLink_\(config.url ?? config.id.uuidString)"
                    )
                }
            }
            .frame(minWidth: 250)
            .accessibilityIdentifier("connectionsList")
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        let config = ConnectionConfig()
                        modelContext.insert(config)
                        selection = config
                    }) {
                        Label("Add Connection", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addConnectionButton")
                }
                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        if let selection {
                            modelContext.delete(connectionConfig: selection)
                            self.selection = nil
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selection == nil)
                    .accessibilityIdentifier("deleteConnectionButton")
                }
            }
        } detail: {
            if let selection {
                ConnectionConfigEditView(config: selection)
                    .navigationTitle("Connection Settings")
            } else {
                ContentUnavailableView(
                    "Select a Connection",
                    systemImage: "globe"
                )
                .navigationTitle("Connection Settings")
            }
        }
    }
}

#Preview {
    do {
        let container = try ModelContainer(
            for: ConnectionConfig.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        container.mainContext.insert(
            ConnectionConfig(
                name: "Media",
                host: "example.com",
                user: "user",
                path: "/mnt/media"
            )
        )

        container.mainContext.insert(
            ConnectionConfig(
                host: "example.com",
            )
        )

        return ConnectionConfigListView()
            .modelContainer(container)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
