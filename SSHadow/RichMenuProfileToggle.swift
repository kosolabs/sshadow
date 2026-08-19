import Common
import CoreKit
import FileProvider
import SwiftUI

struct RichMenuProfileToggle: View {
    @Environment(Connections.self) private var connections

    let config: ConnectionConfigModel

    @State private var isHovered = false

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
