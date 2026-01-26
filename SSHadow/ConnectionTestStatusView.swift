import SwiftUI

struct ConnectionTestStatusView: View {
    let status: ConnectionTestStatus

    var body: some View {
        switch status {
        case .notStarted:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing…")
                    .foregroundStyle(.secondary)
            }
        case .success:
            Label(
                "Success",
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green)
        case .invalidConfig(let message):
            Label(
                message,
                systemImage: "xmark.octagon"
            )
            .foregroundStyle(.red)
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
        case .timeout:
            Label(
                "Connection timed out",
                systemImage: "network.slash"
            )
            .foregroundStyle(.red)
        case .userauthPasswordFailed:
            Label(
                "Password authentication failed",
                systemImage: "lock.circle"
            )
            .foregroundStyle(.red)
        case .pathNotADirectory:
            Label(
                "Remote path is not a directory",
                systemImage: "questionmark.folder"
            )
            .foregroundStyle(.red)
        case .pathNotFound:
            Label(
                "Remote path does not exist",
                systemImage: "questionmark.folder"
            )
            .foregroundStyle(.red)
        case .other(let message):
            Label(
                message,
                systemImage: "bolt.slash"
            )
            .foregroundStyle(.red)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ConnectionTestStatusView(status: .notStarted)
        ConnectionTestStatusView(status: .testing)
        ConnectionTestStatusView(status: .success)
        ConnectionTestStatusView(status: .invalidConfig("Missing host"))
        ConnectionTestStatusView(status: .pathNotADirectory)
        ConnectionTestStatusView(status: .pathNotFound)
        ConnectionTestStatusView(status: .other("Network unreachable"))
    }
    .padding()
}
