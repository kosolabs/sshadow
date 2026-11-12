import Common
import CoreKit
import SwiftData
import SwiftUI

private let logger = Logger(category: "SettingsView")

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WindowActivationTracker.self) private var activation
    @Query private var configs: [ConnectionConfigModel]
    @Query private var storedSettings: [SettingsModel]

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                if let settings = storedSettings.first {
                    GeneralSettingsView(settings: settings)
                }
            }
            Tab("Advanced", systemImage: "gearshape.2") {
                if let settings = storedSettings.first {
                    AdvancedSettingsView(settings: settings)
                }
            }
        }
        .frame(width: 600, height: 560)
        .onAppear {
            activation.retain()
            insertSettingsIfMissing()
        }
        .onDisappear { activation.release() }
        .onChange(of: storedSettings.first?.effectivePoll) {
            submitLiveSettings()
        }
        .onChange(of: storedSettings.first?.effectiveIgnoreFilenames) {
            submitLiveSettings()
        }
    }

    private func submitLiveSettings() {
        guard let settings = storedSettings.first else { return }
        for config in configs {
            config.submitLiveSettings(settings: settings)
        }
    }

    private func insertSettingsIfMissing() {
        do {
            _ = try modelContext.settings()
        } catch {
            logger.error("Failed to load settings: \(error)")
        }
    }
}
