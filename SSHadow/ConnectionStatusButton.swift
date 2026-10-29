import CoreKit
import SwiftUI

struct ConnectionStatusAction {
    let title: String
    let systemImage: String
    let perform: () async -> Void

    init?(config: ConnectionConfigModel, status: ConnectionStatus) {
        switch status {
        case .connecting:
            title = "Cancel Connection"
            systemImage = "xmark.circle.fill"
            perform = config.disable
        case .reconnecting, .online:
            title = "Pause Connection"
            systemImage = "pause.circle.fill"
            perform = config.pause
        case .offline(.paused), .offline(.failed):
            title = "Resume Connection"
            systemImage = "play.circle.fill"
            perform = config.enable
        case .disconnecting, .offline(.disabled):
            return nil
        }
    }
}

struct ConnectionStatusButton: View {
    let config: ConnectionConfigModel
    let status: ConnectionStatus

    var body: some View {
        let icon = ConnectionStatusIcon(status: status, variant: .drive)
        if let action = ConnectionStatusAction(config: config, status: status) {
            HoverActionIcon(icon: icon, action: action)
        } else {
            icon.frame(width: 20, alignment: .center)
        }
    }
}

private struct HoverActionIcon: View {
    let icon: ConnectionStatusIcon
    let action: ConnectionStatusAction

    @State private var isHovered = false

    var body: some View {
        Button {
            Task { await action.perform() }
        } label: {
            if isHovered {
                Image(systemName: action.systemImage)
                    .foregroundStyle(.secondary)
            } else {
                icon
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(action.title)
        .frame(width: 20, alignment: .center)
    }
}
