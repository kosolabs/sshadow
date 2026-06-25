import Common
import Foundation
import SwiftData
import SwiftUI

struct RichMenuMainView: View {
    @Environment(ConnectionCoordinator.self) private var coordinator

    @Query(sort: \ConnectionProfile.host) private var configs:
        [ConnectionProfile]

    @State private var isPolling = false
    @State private var isDebug = false
    @State private var isSettingsHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        .frame(width: 320)
        .onAppear {
            isDebug = NSEvent.modifierFlags.contains(.option)
        }
    }
}
