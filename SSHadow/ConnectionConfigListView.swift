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
                            .foregroundColor(.primary)
                            VStack(alignment: .leading) {
                                if let name = config.name {
                                    Text(name)
                                    Text(config.description)
                                        .font(.caption)
                                } else {
                                    Text(config.description)
                                }
                            }
                        }
                    }
                }
                .onDelete { indices in
                    for index in indices {
                        modelContext.delete(configs[index])
                    }
                }
            }
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
                }
                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        if let selection {
                            modelContext.delete(selection)
                            self.selection = nil
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selection == nil)
                }
            }
        } detail: {
            if let selection {
                ConnectionConfigEditView(config: selection)
            } else {
                ContentUnavailableView(
                    "Select a Connection",
                    systemImage: "globe"
                )
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

        return ConnectionConfigListView()
            .modelContainer(container)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
