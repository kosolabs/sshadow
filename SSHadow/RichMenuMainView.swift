import Common
import CoreKit
import Foundation
import SwiftData
import SwiftUI

struct RichMenuMainView: View {
    @Environment(Transfers<ContinuousClock>.self) private var transfers
    @Environment(ConnectionsNavigation.self) private var connectionsNavigation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @Query(sort: \ConnectionConfigModel.host) private var configs: [ConnectionConfigModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RichMenuHeading(title: "Connections")

            if configs.isEmpty {
                VStack(spacing: 8) {
                    Text("Mount a remote directory over SSH in Finder.")
                        .foregroundStyle(.secondary)

                    Button {
                        NSApp.dismissMenuBarExtra()
                        connectionsNavigation.addConnection(to: modelContext)
                        openWindow.inFront(id: "connections")
                    } label: {
                        Label("Add Your First Connection", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(8)
            } else {
                ForEach(configs) { config in
                    RichMenuProfileToggle(config: config)
                }
            }

            Divider().padding(.vertical, 4)

            if !transfers.value.isEmpty {
                RichMenuHeading(title: "Transfers")

                RichMenuTransfers(transfers: transfers)

                Divider().padding(.vertical, 4)
            }

            RichMenuButton {
                openWindow.inFront(id: "connections")
            } label: {
                RichMenuLabel(
                    "Connections…",
                    systemImage: "externaldrive.badge.icloud"
                )
            }

            RichMenuButton {
                openSettings.inFront()
            } label: {
                RichMenuLabel(
                    "Settings…",
                    systemImage: "gear",
                    shortcut: .init(",", modifiers: .command)
                )
            }

            RichMenuButton {
                openWindow.inFront(id: "events")
            } label: {
                RichMenuLabel(
                    "Event Log",
                    systemImage: "list.bullet.rectangle"
                )
            }

            RichMenuButton {
                openWindow.inFront(id: "about")
            } label: {
                RichMenuLabel("About SSHadow", systemImage: "info.circle")
            }

            Divider().padding(.vertical, 4)

            RichMenuButton {
                NSApplication.shared.terminate(nil)
            } label: {
                RichMenuLabel(
                    "Quit SSHadow",
                    systemImage: "power",
                    shortcut: .init("q", modifiers: .command)
                )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(width: 400)
    }
}
