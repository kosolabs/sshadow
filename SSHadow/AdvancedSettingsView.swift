import CoreKit
import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                AppliesOnRestartNote()
            }

            Section {
                DurationPicker(
                    title: "Check Open Folders Every",
                    seconds: $settings.watchedPollIntervalSeconds,
                    defaultValue: SettingsModel.defaultWatchedPollInterval,
                    choices: [5, 10, 30, 60, 300]
                )
                .accessibilityIdentifier("watchedPollIntervalPicker")
                DurationPicker(
                    title: "Pause Open Folder Checks After",
                    seconds: $settings.watchedPollIdleThresholdSeconds,
                    defaultValue: SettingsModel.defaultWatchedPollIdleThreshold,
                    choices: [60, 120, 300, 600, 1800]
                )
                .accessibilityIdentifier("watchedPollIdleThresholdPicker")
                DurationPicker(
                    title: "Pause Remote Change Checks After",
                    seconds: $settings.pollIdleThresholdSeconds,
                    defaultValue: SettingsModel.defaultPollIdleThreshold,
                    choices: [300, 600, 1800, 3600, 14400]
                )
                .accessibilityIdentifier("pollIdleThresholdPicker")
            } header: {
                Text("Sync")
            } footer: {
                Group {
                    if settings.effectivePollsAutomatically {
                        Text(
                            "Folders open in Finder are checked more often than the rest. Checks pause once the Mac has had no keyboard or mouse activity for the time shown, and resume when you return."
                        )
                    } else {
                        Text(
                            "Check for Remote Changes is set to Manually in General, so SSHadow doesn't check on its own."
                        )
                    }
                }
                .foregroundStyle(.secondary)
            }
            .disabled(!settings.effectivePollsAutomatically)

            Section {
                DurationPicker(
                    title: "Connection Timeout",
                    seconds: $settings.connectTimeoutSeconds,
                    defaultValue: SettingsModel.defaultConnectTimeout,
                    choices: [10, 15, 30, 60, 120, 300]
                )
                .accessibilityIdentifier("connectTimeoutPicker")
                DurationPicker(
                    title: "Maximum Reconnect Delay",
                    seconds: $settings.maxReconnectDelaySeconds,
                    defaultValue: SettingsModel.defaultMaxReconnectDelay,
                    choices: [15, 30, 60, 300, 900]
                )
                .accessibilityIdentifier("maxReconnectDelayPicker")
            } header: {
                Text("Connection")
            } footer: {
                Text(
                    "The timeout is how long SSHadow waits for a server to respond, both when connecting and before treating an unresponsive connection as lost. After a connection drops, SSHadow retries with growing delays, up to the maximum."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
