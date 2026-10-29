import Common
import CoreKit
import Foundation
import SwiftData
import SwiftUI

struct RichMenuMainView: View {
    @Environment(Connections.self) private var connections
    @Environment(Transfers<ContinuousClock>.self) private var transfers
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \ConnectionConfigModel.host) private var configs:
        [ConnectionConfigModel]

    @State private var isPolling = false
    @State private var isDebug = false
    @State private var isSettingsHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RichMenuHeading(title: "Connections")

            if configs.isEmpty {
                VStack(spacing: 8) {
                    Text("Mount a remote directory over SSH in Finder.")
                        .foregroundStyle(.secondary)

                    Button {
                        NSApp.dismissMenuBarExtra()
                        settingsNavigation.addConnection(to: modelContext)
                        openWindow.inFront(id: "settings")
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
                openWindow.inFront(id: "settings")
            } label: {
                RichMenuLabel("Connections & Settings…", systemImage: "gear")
            }

            RichMenuButton {
                openWindow.inFront(id: "events")
            } label: {
                RichMenuLabel(
                    "Event Log",
                    systemImage: "list.bullet.rectangle"
                )
            }

            if isDebug {
                RichMenuButton {
                    Task {
                        isPolling = true
                        defer { isPolling = false }
                        for config in configs {
                            if config.isEnabled() {
                                await config.poll()
                            }
                        }
                    }
                } label: {
                    RichMenuLabel(title: "Poll for Remote Changes") {
                        if isPolling {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(configs.filter({ c in c.enabled }).isEmpty)
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
        .onAppear {
            isDebug = NSEvent.modifierFlags.contains(.option)
        }
    }}
