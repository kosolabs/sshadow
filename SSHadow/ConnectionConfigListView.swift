import Common
import CoreKit
import Foundation
import SwiftData
import SwiftUI

struct ConnectionConfigListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConnectionConfigModel.host) private var configs:
        [ConnectionConfigModel]

    @State private var selection: ConnectionConfigModel?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(configs) { config in
                        NavigationLink(value: config) {
                            HStack {
                                Image(systemName: "externaldrive.badge.icloud")
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
                    }
                }

                Divider()

                HStack(spacing: 0) {
                    Button {
                        let config = ConnectionConfigModel()
                        modelContext.insert(config)
                        selection = config
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 20)
                    }
                    .help("Add Connection")

                    Divider().frame(height: 16)

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
                        Image(systemName: "minus")
                            .frame(width: 24, height: 20)
                    }
                    .disabled(selection == nil)
                    .help("Remove Connection")

                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .frame(width: 300)

            Divider()

            Group {
                if let selection {
                    ConnectionConfigEditView(config: selection)
                } else {
                    ContentUnavailableView(
                        "Select a Connection",
                        systemImage: "globe"
                    )
                }
            }
            .frame(width: 500)
        }
        .frame(height: 600)
    }
}
