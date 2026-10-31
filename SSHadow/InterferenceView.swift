import CoreKit
import SwiftUI

struct InterferenceView: View {
    @Environment(WindowActivationTracker.self) private var activation

    let fix: InterferenceFix

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Another Copy of SSHadow Is Interfering")
                .font(.title3)
                .fontWeight(.semibold)

            Text(
                "\(fix.otherCopy) is syncing your folders instead of this one, "
                    + "so SSHadow can't sync them."
            )

            Step(number: 1, text: "Run this command in Terminal so macOS stops using the other copy:") {
                Text(fix.command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Text(
                    "This also restarts the part of macOS that syncs files, which "
                        + "briefly interrupts apps like iCloud Drive."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Copy Command") {
                    NSPasteboard.general.copy(fix.command)
                }
            }

            Step(number: 2, text: "If you don't need the other copy, move it to the Trash.") {
                if let otherApp = fix.otherApp {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([otherApp])
                    }
                }
            }

            Step(number: 3, text: "Resume the connection from the SSHadow menu.") {}
        }
        .padding(24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { activation.retain() }
        .onDisappear { activation.release() }
    }
}

private struct Step<Content: View>: View {
    let number: Int
    let text: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                content
            }
        }
    }
}
