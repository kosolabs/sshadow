import Common
import SwiftUI

struct AboutView: View {
    @Environment(WindowActivationTracker.self) private var activation

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("SSHadow")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 2) {
                Text("Version \(SSHadow.version)")
                Text("Build \(SSHadow.build)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 280)
        .onAppear { activation.retain() }
        .onDisappear { activation.release() }
    }
}
