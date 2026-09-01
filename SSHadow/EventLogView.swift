import AppKit
import Common
import CoreKit
import Foundation
import SwiftUI

struct EventLogView: View {
    @Environment(Activities.self) private var activities
    @Environment(WindowActivationTracker.self) private var activation

    @State private var selection = Set<Event.ID>()

    private var events: [Event] { activities.events.value }

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "list.bullet.rectangle",
                    description: Text("File operations will appear here as they happen.")
                )
            } else {
                List(selection: $selection) {
                    ForEach(events.reversed()) { event in
                        EventLogRow(event: event)
                    }
                }
                .contextMenu(forSelectionType: Event.ID.self) { ids in
                    Button("Copy") { copy(logLines(for: ids)) }
                        .disabled(ids.isEmpty)
                }
                .onCopyCommand {
                    guard !selection.isEmpty else { return [] }
                    return [NSItemProvider(object: logLines(for: selection) as NSString)]
                }
            }
        }
        .navigationTitle("Event Log")
        .frame(minWidth: 480, minHeight: 320)
        .toolbar {
            Button {
                selection = Set(events.map(\.id))
            } label: {
                Label("Select All", systemImage: "checklist")
            }
            .help("Select all events")
            .keyboardShortcut("a", modifiers: .command)
            .disabled(events.isEmpty)

            Button {
                copy(logLines(for: selection))
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy the selected events to the clipboard")
            .disabled(selection.isEmpty)

            Button {
                selection.removeAll()
                activities.events.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear the event log")
            .disabled(events.isEmpty)
        }
        .onAppear { activation.retain() }
        .onDisappear { activation.release() }
    }

    /// Joins the log lines of the selected events in chronological order.
    private func logLines(for ids: Set<Event.ID>) -> String {
        events
            .filter { ids.contains($0.id) }
            .map(\.logLine)
            .joined(separator: "\n")
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct EventLogRow: View {
    let event: Event

    private var systemImage: String {
        switch event.outcome {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "minus.circle.fill"
        }
    }

    private var iconColor: Color {
        switch event.outcome {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    private var detail: String? {
        switch event.outcome {
        case .succeeded(let detail): detail
        case .failed(let reason): reason
        case .cancelled: nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.operation.description.capitalizedFirst)
                    .lineLimit(2)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 8)

            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

extension String {
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
