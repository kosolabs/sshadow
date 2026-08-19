import CoreKit
import SwiftUI

struct ConnectionStatusIcon: View {
    enum Variant {
        case checkmark
        case drive
    }

    let status: ConnectionStatus
    let variant: Variant

    var body: some View {
        switch status {
        case .connecting, .reconnecting:
            ProgressView()
                .controlSize(.small)
        case .online:
            switch variant {
            case .checkmark:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .drive:
                Image(systemName: "externaldrive.badge.icloud")
                    .foregroundStyle(.green)
            }
        case .offline(.paused):
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.secondary)
        case .offline(.failed(let error)):
            Image(systemName: error.systemImage)
                .foregroundStyle(.red)
        case .offline(.disabled):
            switch variant {
            case .checkmark:
                Image(systemName: "slash.circle.fill")
                    .foregroundStyle(.secondary)
            case .drive:
                Image(systemName: "externaldrive.badge.icloud")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
