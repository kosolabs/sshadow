import CoreKit
import SwiftUI

struct EventLogView: View {
    @Environment(Events<ContinuousClock>.self) private var events
    @Environment(WindowActivationTracker.self) private var activation

    @State private var selection = Set<Event.ID>()

    var body: some View {
        Group {
            if events.value.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "list.bullet.rectangle",
                    description: Text(
                        "Events will appear here as they happen."
                    )
                )
            } else {
                List(selection: $selection) {
                    ForEach(events.value.reversed()) { event in
                        EventLogRow(event: event)
                    }
                }
                .contextMenu(forSelectionType: Event.ID.self) { ids in
                    Button("Copy") { copy(logLines(for: ids)) }
                        .disabled(ids.isEmpty)
                }
                .onCopyCommand {
                    guard !selection.isEmpty else { return [] }
                    return [
                        NSItemProvider(
                            object: logLines(for: selection) as NSString
                        )
                    ]
                }
            }
        }
        .navigationTitle("Event Log")
        .frame(minWidth: 480, minHeight: 320)
        .toolbar {
            Button {
                selection = Set(events.value.map(\.id))
            } label: {
                Label("Select All", systemImage: "checklist")
            }
            .help("Select all events")
            .keyboardShortcut("a", modifiers: .command)
            .disabled(events.value.isEmpty)

            Button {
                copy(logLines(for: selection))
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy the selected events to the clipboard")
            .disabled(selection.isEmpty)

            Button {
                selection.removeAll()
                events.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear the event log")
            .disabled(events.value.isEmpty)
        }
        .onAppear { activation.retain() }
        .onDisappear { activation.release() }
    }

    private func logLines(for ids: Set<Event.ID>) -> String {
        events.value
            .filter { ids.contains($0.id) }
            .map(\.logLine)
            .joined(separator: "\n")
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
