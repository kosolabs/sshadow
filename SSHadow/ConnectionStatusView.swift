import Common
import CoreKit
import SwiftLibSSH
import SwiftUI

struct ConnectionStatusView: View {
    let status: ConnectionStatus

    var body: some View {
        switch status {
        case .offline(let reason):
            switch reason {
            case .disabled:
                EmptyView()
            case .paused:
                Label("Paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.secondary)
            case .failed(let error):
                Label(error.message, systemImage: error.systemImage)
                    .foregroundStyle(.red)
            }
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Connecting…").foregroundStyle(.secondary)
            }
        case .reconnecting(let error, let nextAttempt):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                ReconnectingLabel(error: error, nextAttempt: nextAttempt)
                    .foregroundStyle(.secondary)
            }
        case .online:
            Label("Connected", systemImage: "checkmark.circle.fill")
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
                    Int(nextAttempt.timeIntervalSince(context.date).rounded(.up))
                )
                Text("\(prefix). Reconnecting in \(remaining)s…")
            }
        } else {
            Text("\(prefix). Reconnecting…")
        }
    }
}

extension ConnectionError {
    fileprivate var message: String {
        switch self {
        case .unknownHost: "Unknown host"
        case .connectionRefused: "Connection refused"
        case .connectionTimedOut: "Connection timed out"
        case .invalidPrivateKey: "Invalid private key"
        case .authenticationFailed: "Authentication failed"
        case .remotePathNotFound: "Remote path does not exist"
        case .remotePathNotDirectory: "Remote path is not a directory"
        case .unknown(_, _, let message): "Other: \(message)"
        }
    }

    fileprivate var systemImage: String {
        switch self {
        case .invalidPrivateKey, .authenticationFailed:
            "lock.circle"
        case .unknownHost, .connectionRefused, .connectionTimedOut:
            "network.slash"
        case .remotePathNotFound, .remotePathNotDirectory:
            "questionmark.folder"
        case .unknown:
            "bolt.slash"
        }
    }
}
