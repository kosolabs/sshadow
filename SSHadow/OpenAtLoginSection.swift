import AppKit
import Common
import ServiceManagement
import SwiftUI

private let logger = Logger(category: "OpenAtLogin")

struct OpenAtLoginSection: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    private var opensAtLogin: Binding<Bool> {
        Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { setOpensAtLogin($0) }
        )
    }

    var body: some View {
        Section {
            Toggle("Open at Login", isOn: opensAtLogin)
                .accessibilityIdentifier("openAtLoginToggle")
            if status == .requiresApproval {
                LabeledContent {
                    Button("Open Login Items…") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } label: {
                    Text("Allow SSHadow in Login Items to finish turning this on.")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if let failure {
                Text(failure)
                    .foregroundStyle(.red)
            }
        }
        .onAppear(perform: refreshStatus)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        status = SMAppService.mainApp.status
    }

    private func setOpensAtLogin(_ opens: Bool) {
        do {
            if opens {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failure = nil
            logger.notice("Open at login \(opens ? "enabled" : "disabled")")
        } catch {
            logger.error("Failed to set open at login to \(opens): \(error)")
            failure = error.localizedDescription
        }
        refreshStatus()
    }
}
