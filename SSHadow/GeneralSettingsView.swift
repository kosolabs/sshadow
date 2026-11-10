import CoreKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsModel

    private static let checkIntervalChoices = [60, 300, 900, 1800, 3600]

    private var ignoreFilenames: Binding<[String]> {
        Binding(
            get: { settings.effectiveIgnoreFilenames },
            set: { settings.ignoreFilenames = $0 }
        )
    }

    private var ignoreFilesError: ConnectionConfig.ValidationError? {
        do {
            try settings.validate()
            return nil
        } catch {
            return error
        }
    }

    var body: some View {
        Form {
            OpenAtLoginSection()

            Section {
                Picker("Check for Remote Changes", selection: $settings.pollFrequency) {
                    ForEach(Self.checkIntervalChoices, id: \.self) { choice in
                        checkIntervalLabel(choice)
                    }
                    Divider()
                    Text("Manually").tag(SettingsModel.PollFrequency.manual)
                }
                .accessibilityIdentifier("checkFrequencyPicker")
            } header: {
                Text("Sync")
            } footer: {
                Group {
                    if settings.effectivePollsAutomatically {
                        Text(
                            "How often SSHadow looks for changes made on the server. Folders open in Finder are checked more often."
                        )
                    } else {
                        Text(
                            "Changes made on the server appear when you choose Check for Remote Changes in the menu bar."
                        )
                    }
                }
                .foregroundStyle(.secondary)
            }

            IgnoreFilesSection(
                customizes: $settings.customizesIgnoreFiles,
                filenames: ignoreFilenames,
                inheritedNote: "These are SSHadow's defaults.",
                error: ignoreFilesError
            ) {
                Text("Connections use these unless they customize their own.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func checkIntervalLabel(_ seconds: Int) -> some View {
        let duration = Duration.seconds(seconds)
        if duration == SettingsModel.defaultPollInterval {
            Text("Every \(duration.spelledOut) (Default)")
                .tag(SettingsModel.PollFrequency.automatic(intervalSeconds: nil))
        } else {
            Text("Every \(duration.spelledOut)")
                .tag(
                    SettingsModel.PollFrequency.automatic(
                        intervalSeconds: seconds
                    )
                )
        }
    }
}
