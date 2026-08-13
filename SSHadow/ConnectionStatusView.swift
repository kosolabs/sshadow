import Common
import CoreKit
import SwiftLibSSH
import SwiftUI

struct ConnectionStatusView: View {
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
        } else if let testError = error as? SSHClient.TestError {
            switch testError {
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
            case .authenticationFailed:
                Label(
                    "Authentication failed",
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
                    "Other: \(testError.localizedDescription)",
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
