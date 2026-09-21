import Common
import CoreKit
import FileProvider
import SwiftUI

private let logger = Logger(category: "RichMenuProfileToggle")

struct RichMenuProfileToggle: View {
    @Environment(Connections.self) private var connections

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
                .onTapGesture { openInFinder() }
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
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8).fill(
                isHovered && config.isEnabled()
                    ? Color.primary : Color.clear
            )
        )
        .onHover { isHovered = $0 }
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
}
