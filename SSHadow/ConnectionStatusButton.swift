import CoreKit
import SwiftUI

struct ConnectionStatusButton: View {
    let config: ConnectionConfigModel
    let status: ConnectionStatus

    var body: some View {
        switch status {
        case .connecting, .reconnecting, .online:
            HoverActionIcon(
                icon: ConnectionStatusIcon(status: status, variant: .drive),
                variant: config.isEnabled()
                    ? .hover(
                        icon: "pause.circle.fill",
                        help: "Pause connection",
                        action: config.pause
                    ) : .plain
            )
        case .offline(.paused), .offline(.failed):
            HoverActionIcon(
                icon: ConnectionStatusIcon(status: status, variant: .drive),
                variant: config.isEnabled()
                    ? .hover(
                        icon: "play.circle.fill",
                        help: "Resume connection",
                        action: config.enable
                    ) : .plain
            )
        case .offline(.disabled):
            HoverActionIcon(
                icon: ConnectionStatusIcon(status: status, variant: .drive),
                variant: .plain
            )
        }
    }
}

private struct HoverActionIcon: View {
    enum Variant {
        case plain
        case hover(icon: String, help: String, action: () async throws -> Void)
    }

    let icon: ConnectionStatusIcon
    let variant: Variant

    @State private var isHovered = false

    var body: some View {
        switch variant {
        case .plain:
            icon.frame(width: 20, alignment: .center)
        case .hover(let hoverIcon, let help, let action):
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
}
