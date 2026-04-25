import Common
import Foundation
import SwiftData
import SwiftUI

struct ConnectionProfileListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConnectionProfile.host) private var configs:
        [ConnectionProfile]

    @State private var selection: ConnectionProfile?

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
                                    Text(config.displayUrl).font(.caption)
                                } else {
                                    Text(config.displayUrl)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier(
                        "connectionLink_\(config.url)"
                    )
                }
            }
            .frame(minWidth: 250, minHeight: 500)
            .accessibilityIdentifier("connectionsList")
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        let config = ConnectionProfile()
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
                            Task {
                                try? await modelContext.delete(
                                    connectionConfig: selection
                                )
                            }
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
                ConnectionProfileEditView(config: selection)
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
            for: ConnectionProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        container.mainContext.insert(
            ConnectionProfile(
                name: "Media",
                host: "example.com",
                user: "user",
                path: "/mnt/media"
            )
        )

        container.mainContext.insert(
            ConnectionProfile(
                host: "example.com",
            )
        )

        return ConnectionProfileListView()
            .modelContainer(container)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
