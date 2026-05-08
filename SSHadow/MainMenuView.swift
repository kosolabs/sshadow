import Common
import Foundation
import SwiftData
import SwiftUI

struct MainMenuView: View {
    @Environment(\.openWindow) private var openWindow

    @Binding var isBusy: Bool

    @Query(sort: \ConnectionProfile.host) private var configs:
        [ConnectionProfile]

    var body: some View {
        Section("Connections") {
            ForEach(configs) { config in
                Toggle(
                    config.name ?? config.displayUrl,
                    isOn: Binding(
                        get: { config.isEnabled() },
                        set: { newValue in
                            Task {
                                isBusy = true
                                try? await newValue
                                    ? config.enable() : config.disable()
                                isBusy = false
                            }
                        }
                    )
                )
            }
        }

        if !configs.isEmpty {
            Divider()
        }

        Button {
            openWindow(id: "settings")
        } label: {
            Label("Open SSHadow Settings...", systemImage: "gear")
        }
        .keyboardShortcut(",")

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit SSHadow", systemImage: "power")
        }
        .keyboardShortcut("q")
    }
}
