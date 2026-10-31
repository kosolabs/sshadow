import CoreKit
import SwiftUI

struct UnreachableView: View {
    @Environment(WindowActivationTracker.self) private var activation

    let fix: UnreachableFix

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSHadow Can't Connect to Its Extension")
                .font(.title3)
                .fontWeight(.semibold)

            if let otherCopy = fix.otherCopy {
                Text(
                    "\(otherCopy) is syncing your folders instead of this one, "
                        + "so SSHadow can't sync them."
                )
            } else {
                Text(
                    "macOS didn't let SSHadow reach the part of it that syncs "
                        + "your files."
                )
            }

            FixStep(number: 1, text: "Run this command in Terminal:") {
                FixCommand(
                    command: fix.command,
                    note:
                        "This restarts the part of macOS that syncs files, "
                        + "which briefly interrupts apps like iCloud Drive."
                )
            }

            if fix.otherCopy != nil {
                FixStep(
                    number: 2,
                    text:
                        "If you don't need the other copy, move it to the Trash."
                ) {
                    if let otherApp = fix.otherApp {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([
                                otherApp
                            ])
                        }
                    }
                }
            }

            FixStep(
                number: fix.otherCopy == nil ? 2 : 3,
                text: "Resume the connection from the SSHadow menu."
            ) {}
        }
        .padding(24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { activation.retain() }
        .onDisappear { activation.release() }
    }
}

private struct FixStep<Content: View>: View {
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

private struct FixCommand: View {
    let command: String
    let note: String

    var body: some View {
        Text(command)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        Text(note)
            .font(.caption)
            .foregroundStyle(.secondary)
        Button("Copy Command") {
            NSPasteboard.general.copy(command)
        }
    }
}
