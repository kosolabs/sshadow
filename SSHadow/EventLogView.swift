import CoreKit
import SwiftData
import SwiftUI

struct EventLogView: View {
    @Environment(WindowActivationTracker.self) private var activation

    @State private var filter = EventFilter()
    @State private var search = ""

    var body: some View {
        EventLogList(filter: $filter, search: search)
            .navigationTitle("Event Log")
            .searchable(text: $search, prompt: "Search")
            .frame(minWidth: 480, minHeight: 320)
            .onAppear { activation.retain() }
            .onDisappear { activation.release() }
    }
}

private struct EventLogList: View {
    private static let maxShown = 10_000

    private static var anyEvent: FetchDescriptor<EventModel> {
        var descriptor = FetchDescriptor<EventModel>()
        descriptor.fetchLimit = 1
        return descriptor
    }

    @Environment(Events<ContinuousClock>.self) private var events
    @Environment(\.modelContext) private var modelContext

    @Query private var anyEvent: [EventModel]
    @Query private var visibleEvents: [EventModel]

    @Binding private var filter: EventFilter
    private let search: String
    @State private var selection = Set<EventModel.ID>()
    @State private var total: Int?

    init(filter: Binding<EventFilter>, search: String) {
        _filter = filter
        self.search = search
        _anyEvent = Query(Self.anyEvent)
        var shown = filter.wrappedValue.descriptor(matching: search)
        shown.fetchLimit = Self.maxShown
        _visibleEvents = Query(shown)
    }

    private struct TotalKey: Hashable {
        let filter: EventFilter
        let search: String
        let newest: EventModel.ID?
        let shown: Int
    }

    private var totalKey: TotalKey {
        TotalKey(
            filter: filter,
            search: search,
            newest: visibleEvents.first?.id,
            shown: visibleEvents.count
        )
    }

    private var subtitle: String {
        guard let total, total > 0 else { return "" }
        let counted = total == 1 ? "1 event" : "\(total.formatted()) events"
        guard total > visibleEvents.count else { return counted }
        return "Newest \(visibleEvents.count.formatted()) of \(counted)"
    }

    var body: some View {
        Group {
            if anyEvent.isEmpty {
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
                    ForEach(visibleEvents) { model in
                        if let event = Event(from: model) {
                            EventLogRow(event: event)
                        }
                    }
                }
                .contextMenu(forSelectionType: EventModel.ID.self) { ids in
                    Button("Copy") {
                        NSPasteboard.general.copy(logLines(for: ids))
                    }
                    .disabled(ids.isEmpty)
                }
                .onCopyCommand {
                    [NSItemProvider(object: logLines(for: copied) as NSString)]
                }
            }
        }
        .navigationSubtitle(subtitle)
        .task(id: totalKey) {
            total = try? modelContext.fetchCount(
                filter.descriptor(matching: search)
            )
        }
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
                if selection.isEmpty {
                    selection = Set(visibleEvents.map(\.id))
                } else {
                    selection.removeAll()
                }
            } label: {
                if selection.isEmpty {
                    Label("Select All", systemImage: "checklist")
                } else {
                    Label("Select None", systemImage: "checklist.unchecked")
                }
            }
            .help(selection.isEmpty ? "Select all events shown" : "Deselect all events")
            .keyboardShortcut("a", modifiers: .command)
            .disabled(visibleEvents.isEmpty)

            Button {
                NSPasteboard.general.copy(logLines(for: copied))
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help(
                selection.isEmpty
                    ? "Copy all events shown to the clipboard"
                    : "Copy the selected events to the clipboard"
            )
            .disabled(visibleEvents.isEmpty)

            Button {
                selection.removeAll()
                events.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear the event log")
            .disabled(anyEvent.isEmpty)
        }
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

    private var copied: Set<EventModel.ID> {
        selection.isEmpty ? Set(visibleEvents.map(\.id)) : selection
    }

    private func logLines(for ids: Set<EventModel.ID>) -> String {
        visibleEvents
            .reversed()
            .filter { ids.contains($0.id) }
            .compactMap { Event(from: $0)?.logLine }
            .joined(separator: "\n")
    }
}
