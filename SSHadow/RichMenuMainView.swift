import AgentKit
import Common
import Foundation
import SwiftData
import SwiftUI

struct RichMenuMainView: View {
    @Environment(ConnectionCoordinator.self) private var coordinator
    @Environment(Transfers.self) private var transfers
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \ConnectionConfigModel.host) private var configs:
        [ConnectionConfigModel]

    @State private var isPolling = false
    @State private var isDebug = false
    @State private var isSettingsHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !transfers.isEmpty {
                RichMenuHeading(title: "Transfers")

                ForEach(transfers.value) { transfer in
                    RichMenuTransfer(transfer: transfer)
                }

                Divider().padding(.vertical, 4)
            }

            if !configs.isEmpty {
                RichMenuHeading(title: "Connections")

                ForEach(configs) { config in
                    RichMenuProfileToggle(config: config)
                }

                Divider().padding(.vertical, 4)
            }

            RichMenuSettingsButton {
                RichMenuLabel(
                    "Open SSHadow Settings...",
                    systemImage: "gear",
                    shortcut: .init(",", modifiers: .command)
                )
            }

            if isDebug {
                RichMenuButton {
                    Task {
                        isPolling = true
                        defer { isPolling = false }
                        for config in configs {
                            if config.isEnabled() {
                                try await config.poll()
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
                NSApp.activate()
                openWindow(id: "about")
            } label: {
                RichMenuLabel("About SSHadow", systemImage: "info.circle")
            }

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
    }

}
