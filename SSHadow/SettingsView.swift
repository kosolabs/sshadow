import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab {
                ConnectionProfileListView()
            } label: {
                Label(
                    "Connections",
                    systemImage: "externaldrive.badge.icloud"
                )
            }
        }
    }
}
