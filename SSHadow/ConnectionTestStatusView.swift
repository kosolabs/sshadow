import AgentKit
import Common
import SwiftUI
import SwiftLibSSH

struct ConnectionTestStatusView: View {
    let testing: Bool
    let error: Error?

    var body: some View {
        if testing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Verifying…")
                    .foregroundStyle(.secondary)
            }
        } else if let validationError = error
            as? ConnectionConfigModel.ValidationError
        {
            switch validationError {
            case .passwordNil:
                Label(
                    "Password is required",
                    systemImage: "lock.circle"
                )
                .foregroundStyle(.red)
            case .privateKeyUrlNil:
                Label(
                    "Private key is required",
                    systemImage: "lock.circle"
                )
                .foregroundStyle(.red)
            default:
                Label(
                    "Other: \(validationError.localizedDescription)",
                    systemImage: "bolt.slash"
                )
                .foregroundStyle(.red)
            }
        } else if let agentError = error as? SSHClient.TestError {
            switch agentError {
            case .unknownHost:
                Label(
                    "Unknown host",
                    systemImage: "network.slash"
                )
                .foregroundStyle(.red)
            case .connectionRefused:
                Label(
                    "Connection refused",
                    systemImage: "network.slash"
                )
                .foregroundStyle(.red)
            case .connectionTimedOut:
                Label(
                    "Connection timed out",
                    systemImage: "network.slash"
                )
                .foregroundStyle(.red)
            case .invalidPrivateKey:
                Label(
                    "Invalid private key",
                    systemImage: "lock.circle"
                )
                .foregroundStyle(.red)
            case .passwordAuthFailed:
                Label(
                    "Password authentication failed",
                    systemImage: "lock.circle"
                )
                .foregroundStyle(.red)
            case .remotePathNotDirectory:
                Label(
                    "Remote path is not a directory",
                    systemImage: "questionmark.folder"
                )
                .foregroundStyle(.red)
            case .remotePathNotFound:
                Label(
                    "Remote path does not exist",
                    systemImage: "questionmark.folder"
                )
                .foregroundStyle(.red)
            default:
                Label(
                    "Other: \(agentError.localizedDescription)",
                    systemImage: "bolt.slash"
                )
                .foregroundStyle(.red)
            }
        } else if let error {
            Label(
                "Other: \(error.localizedDescription)",
                systemImage: "bolt.slash"
            )
            .foregroundStyle(.red)
        } else {
            EmptyView()
        }
    }
}
