import CoreKit
import SwiftUI

struct ConnectionStatusText: View {
    let status: ConnectionStatus

    var body: some View {
        switch status {
        case .offline(.disabled):
            Text("Disabled")
                .foregroundStyle(.secondary)
        case .offline(.paused):
            Text("Paused")
                .foregroundStyle(.secondary)
        case .offline(.failed(let error)):
            Text(error.message)
                .foregroundStyle(.red)
        case .connecting:
            Text("Connecting…")
                .foregroundStyle(.secondary)
        case .reconnecting(let error, let nextAttempt):
            ReconnectingLabel(error: error, nextAttempt: nextAttempt)
                .foregroundStyle(.secondary)
        case .online:
            Text("Connected")
                .foregroundStyle(.green)
        }
    }
}

private struct ReconnectingLabel: View {
    let error: ConnectionError?
    let nextAttempt: Date?

    var body: some View {
        let prefix = error?.message ?? "Connection lost"
        if let nextAttempt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(
                    0,
                    Int(
                        nextAttempt.timeIntervalSince(context.date).rounded(.up)
                    )
                )
                Text("\(prefix). Reconnecting in \(remaining)s…")
            }
        } else {
            Text("\(prefix). Reconnecting…")
        }
    }
}
