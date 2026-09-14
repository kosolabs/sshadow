import CoreKit
import SwiftUI

struct ConnectionStatusButton: View {
    let config: ConnectionConfigModel
    let status: ConnectionStatus

    var body: some View {
        switch config.isEnabled() {
        case false:
            ConnectionStatusIcon(status: status, variant: .drive)
                .frame(width: 20, alignment: .center)
        case true:
            switch status {
            case .reconnecting, .online:
                HoverActionIcon(
                    icon: ConnectionStatusIcon(status: status, variant: .drive),
                    hoverIcon: "pause.circle.fill",
                    help: "Pause connection",
                    action: config.pause
                )
            case .offline(.paused), .offline(.failed):
                HoverActionIcon(
                    icon: ConnectionStatusIcon(status: status, variant: .drive),
                    hoverIcon: "play.circle.fill",
                    help: "Resume connection",
                    action: config.enable
                )
            case .connecting, .disconnecting, .offline(.disabled):
                ConnectionStatusIcon(status: status, variant: .drive)
                    .frame(width: 20, alignment: .center)
            }
        }
    }
}

private struct HoverActionIcon: View {
    let icon: ConnectionStatusIcon
    let hoverIcon: String
    let help: String
    let action: () async throws -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            Task { try await action() }
        } label: {
            if isHovered {
                Image(systemName: hoverIcon)
                    .foregroundStyle(.secondary)
            } else {
                icon
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .frame(width: 20, alignment: .center)
    }
}
