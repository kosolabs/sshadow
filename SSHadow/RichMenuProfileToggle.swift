import Common
import CoreKit
import FileProvider
import SwiftUI

private let logger = Logger(category: "RichMenuProfileToggle")

struct RichMenuProfileToggle: View {
    @Environment(Connections.self) private var connections
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @Environment(\.openWindow) private var openWindow

    let config: ConnectionConfigModel

    @State private var isHovered = false
    @State private var folderUrl: URL?

    private var enabled: Binding<Bool> {
        Binding<Bool>(
            get: { config.isEnabled() },
            set: { config.setEnabled($0) }
        )
    }

    private var status: ConnectionStatus {
        connections.status(for: config.id)
    }

    private var isFailed: Bool {
        switch status {
        case .offline(.failed), .offline(.xpcUnreachable):
            true
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 8) {
                ConnectionStatusButton(config: config, status: status)

                HStack {
                    VStack(alignment: .leading) {
                        if let name = config.name {
                            Text(name)
                            Text(config.displayUrl).font(.caption)
                        } else {
                            Text(config.displayUrl)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    config.isEnabled() ? openInFinder() : editInSettings()
                }
                .help(
                    config.isEnabled() ? "Show in Finder" : "Edit in Settings"
                )
                .draggable(ifAvailable: folderUrl.map(\.shellEscapedPath))

                Toggle(isOn: enabled) {}
                    .toggleStyle(.switch)
                    .disabled(connections.isBusy(id: config.id))
            }

            switch status {
            case .reconnecting, .offline(.failed):
                ConnectionStatusText(status: status)
                    .font(.caption)
                    .padding(.leading, 28)
            case .offline(.xpcUnreachable(let otherExtension)):
                HStack(spacing: 4) {
                    ConnectionStatusText(status: status)
                    Button("How to Fix…") {
                        showFix(otherExtension: otherExtension)
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
                .padding(.leading, 28)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8).fill(
                isHovered ? Color.primary : Color.clear
            )
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Show in Finder", action: openInFinder)
                .disabled(folderUrl == nil)
            Button("Edit Connection…", action: editInSettings)

            Divider()

            if let action = ConnectionStatusAction(
                config: config,
                status: status
            ) {
                Button(action.title) {
                    Task { await action.perform() }
                }
            }
            if case .offline(.xpcUnreachable(let otherExtension)) = status {
                Button("How to Fix…") {
                    showFix(otherExtension: otherExtension)
                }
            }
            Button("Clear Status") {
                Task { await config.clearFailure() }
            }
            .disabled(!isFailed)
            Button("Check for Remote Changes") {
                Task { await config.poll() }
            }
            .disabled(status != .online)

            Divider()

            Button("Copy SSH Command") {
                NSPasteboard.general.copy(config.sshCommand)
            }
            .disabled(config.host.isEmpty)
            Button("Copy Path") {
                if let folderUrl {
                    NSPasteboard.general.copy(
                        folderUrl.path(percentEncoded: false)
                    )
                }
            }
            .disabled(folderUrl == nil)
        }
        .task(id: config.isEnabled()) { folderUrl = await resolveFolderUrl() }
    }

    private func resolveFolderUrl() async -> URL? {
        if config.isEnabled() {
            do {
                return try await config.domain.manager.getUserVisibleURL(
                    for: .rootContainer
                )
            } catch {
                logger.error("Failed to resolve URL for \(config): \(error)")
            }
        }
        return nil
    }

    private func openInFinder() {
        guard let folderUrl else { return }
        NSApp.dismissMenuBarExtra()
        NSWorkspace.shared.activateFileViewerSelecting([folderUrl])
    }

    private func editInSettings() {
        NSApp.dismissMenuBarExtra()
        settingsNavigation.selectedConfig = config
        openWindow.inFront(id: "settings")
    }

    private func showFix(otherExtension: URL?) {
        NSApp.dismissMenuBarExtra()
        openWindow.inFront(
            id: "unreachable",
            value: UnreachableFix(
                otherExtension: otherExtension,
                home: .userHome
            )
        )
    }
}
