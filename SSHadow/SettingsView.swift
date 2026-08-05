import SwiftUI

struct SettingsView: View {
    @Environment(WindowActivationTracker.self) private var activation

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
        .onAppear { activation.retain() }
        .onDisappear { activation.release() }
    }
}
