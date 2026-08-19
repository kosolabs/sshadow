import Common
import CoreKit
import Foundation
import SwiftData
import SwiftUI

struct ConnectionConfigListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Connections.self) private var connections
    @Query(sort: \ConnectionConfigModel.host) private var configs:
        [ConnectionConfigModel]

    @Binding var selection: ConnectionConfigModel?

    var body: some View {
        List(selection: $selection) {
            ForEach(configs) { config in
                HStack {
                    ConnectionStatusButton(
                        config: config,
                        status: connections.status(for: config.id)
                    )
                    .font(.system(size: 18))
                    .padding(.horizontal, 4)

                    VStack(alignment: .leading) {
                        if let name = config.name {
                            Text(name)
                            Text(config.displayUrl).font(.caption)
                        } else {
                            Text(config.displayUrl)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .tag(config)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let config = ConnectionConfigModel()
                    modelContext.insert(config)
                    selection = config
                } label: {
                    Label("Add Connection", systemImage: "plus")
                }
                .help("Add Connection")
            }

            if let selection {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        Task {
                            try? await modelContext.delete(
                                connectionConfig: selection
                            )
                        }
                        self.selection = nil
                    } label: {
                        Label("Remove Connection", systemImage: "trash")
                    }
                    .help("Remove Connection")
                }
            }
        }
    }
}
