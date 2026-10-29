import CoreKit
import SwiftUI

struct EventLogView: View {
    @Environment(Events<ContinuousClock>.self) private var events
    @Environment(WindowActivationTracker.self) private var activation

    @State private var filter = EventFilter()
    @State private var search = ""
    @State private var selection = Set<Event.ID>()

    private var visibleEvents: [Event] {
        events.value.filter { filter.includes($0, matching: search) }
    }

    var body: some View {
        let visibleEvents = visibleEvents
        Group {
            if events.value.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "list.bullet.rectangle",
                    description: Text(
                        "Events will appear here as they happen."
                    )
                )
            } else if visibleEvents.isEmpty, !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if visibleEvents.isEmpty {
                ContentUnavailableView(
                    "No Matching Events",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(
                        "Change the filter to show more events."
                    )
                )
            } else {
                List(selection: $selection) {
                    ForEach(visibleEvents.reversed()) { event in
                        EventLogRow(event: event)
                    }
                }
                .contextMenu(forSelectionType: Event.ID.self) { ids in
                    Button("Copy") {
                        NSPasteboard.general.copy(logLines(for: ids))
                    }
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
        .searchable(text: $search, prompt: "Search")
        .frame(minWidth: 480, minHeight: 320)
        .toolbar {
            Menu {
                Section("Levels") {
                    ForEach(Event.Level.allCases.reversed(), id: \.self) {
                        level in
                        Toggle(level.label.capitalized, isOn: shows(level))
                    }
                }
                Section("Categories") {
                    ForEach(Event.Category.allCases, id: \.self) { category in
                        Toggle(category.label, isOn: shows(category))
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
            }
            .help("Choose which events to show")

            Button {
                selection = Set(visibleEvents.map(\.id))
            } label: {
                Label("Select All", systemImage: "checklist")
            }
            .help("Select all events shown")
            .keyboardShortcut("a", modifiers: .command)
            .disabled(visibleEvents.isEmpty)

            Button {
                NSPasteboard.general.copy(logLines(for: selection))
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

    private func shows(_ level: Event.Level) -> Binding<Bool> {
        Binding(
            get: { !filter.hiddenLevels.contains(level) },
            set: { shown in
                if shown {
                    filter.hiddenLevels.remove(level)
                } else {
                    filter.hiddenLevels.insert(level)
                }
            }
        )
    }

    private func shows(_ category: Event.Category) -> Binding<Bool> {
        Binding(
            get: { !filter.hiddenCategories.contains(category) },
            set: { shown in
                if shown {
                    filter.hiddenCategories.remove(category)
                } else {
                    filter.hiddenCategories.insert(category)
                }
            }
        )
    }

    private func logLines(for ids: Set<Event.ID>) -> String {
        visibleEvents
            .filter { ids.contains($0.id) }
            .map(\.logLine)
            .joined(separator: "\n")
    }
}
