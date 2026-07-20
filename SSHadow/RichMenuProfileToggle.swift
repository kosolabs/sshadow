import AgentKit
import Common
import FileProvider
import SwiftUI

struct RichMenuProfileToggle: View {
    @Environment(ConnectionCoordinator.self) private var coordinator

    let config: ConnectionConfigModel

    @State private var isHovered = false

    private var enabled: Binding<Bool> {
        Binding<Bool>(
            get: { config.isEnabled() },
            set: { coordinator.setEnabled($0, on: config) }
        )
    }

    var body: some View {
        Button {
            openInFinder()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.icloud")
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading) {
                    if let name = config.name {
                        Text(name)
                        Text(config.displayUrl).font(.caption)
                    } else {
                        Text(config.displayUrl)
                    }
                }

                Spacer()

                Toggle(isOn: enabled) {}
                    .toggleStyle(.switch)
                    .disabled(coordinator.isBusy(config))
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
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func openInFinder() {
        guard config.isEnabled() else { return }
        Task {
            let url = try await config.domain.manager.getUserVisibleURL(
                for: .rootContainer
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
            NSApp.dismissMenuBarExtra()
        }
    }
}
