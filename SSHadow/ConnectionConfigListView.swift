import Foundation
import SwiftUI
import SwiftData

struct ConnectionConfigListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConnectionConfig.host) private var configs: [ConnectionConfig]
    
    @State private var selection: ConnectionConfig?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(configs) { config in
                    NavigationLink(value: config) {
                        VStack(alignment: .leading) {
                            Text("\(config.description)")
                        }
                    }
                }
                .onDelete() { indices in
                    for index in indices {
                        modelContext.delete(configs[index])
                    }
                }
            }
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        let config = ConnectionConfig(host: "example.com")
                        modelContext.insert(config)
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
                ContentUnavailableView("Select a Connection", systemImage: "globe")
            }
        }
    }
}


#Preview {
    ConnectionConfigListView()
        .modelContainer(for: ConnectionConfig.self, inMemory: true)
}
