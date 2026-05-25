import Common
import Foundation
import SwiftData
import SwiftUI

struct RichMenuMainView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(ConnectionCoordinator.self) private var coordinator

    @Query(sort: \ConnectionProfile.host) private var configs:
        [ConnectionProfile]

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
                Label("Open SSHadow Settings...", systemImage: "gear")
            }

            RichMenuButton {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit SSHadow", systemImage: "power")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(width: 320)
    }
}
