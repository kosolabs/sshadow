import Common
import Foundation
import SwiftData
import SwiftUI

struct RichMenuMainView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(ConnectionCoordinator.self) private var coordinator

    @Query(sort: \ConnectionProfile.host) private var configs:
        [ConnectionProfile]

    @State private var isPolling = false
    @State private var isDebug = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !configs.isEmpty {
                RichMenuHeading(title: "Connections")

                ForEach(configs) { config in
                    RichMenuProfileToggle(config: config)
                }

                Divider().padding(.vertical, 4)
            }

            RichMenuButton {
                openWindow(id: "settings")
                NSApp.activate()
            } label: {
                RichMenuLabel("Open SSHadow Settings...", systemImage: "gear")
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
                    RichMenuLabel(title: "Poll Remote Changes") {
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
                RichMenuLabel("Quit SSHadow", systemImage: "power")
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
