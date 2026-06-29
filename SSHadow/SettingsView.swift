import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab {
                ConnectionConfigListView()
            } label: {
                Label(
                    "Connections",
                    systemImage: "externaldrive.badge.icloud"
                )
            }
        }
    }
}
