import SwiftUI

struct IgnoreFilenamesList: View {
    @Binding var filenames: [String]
    @State private var selection: Int?
    @State private var editing: Int?
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var rows: [String] {
        editing == filenames.count ? filenames + [draft] : filenames
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(rows.indices, id: \.self) { index in
                    row(at: index)
                        .tag(index)
                        .moveDisabled(editing != nil)
                }
                .onMove(perform: move)
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(minHeight: 80)
            .contextMenu(forSelectionType: Int.self) { indices in
                if let index = indices.first, index < filenames.count {
                    Button("Edit") { edit(index) }
                    Button("Remove") { remove(index) }
                }
            } primaryAction: { indices in
                if let index = indices.first, index < filenames.count {
                    edit(index)
                }
            }
            .accessibilityIdentifier("ignoreFilenamesList")
            HStack(spacing: 0) {
                barButton("Add Ignore File", systemImage: "plus", action: add)
                    .accessibilityIdentifier("addIgnoreFilenameButton")
                Divider().frame(height: 16)
                barButton(
                    "Remove Ignore File",
                    systemImage: "minus",
                    action: removeSelected
                )
                .disabled(selection == nil)
                .accessibilityIdentifier("removeIgnoreFilenameButton")
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func row(at index: Int) -> some View {
        if editing == index {
            TextField("File Name", text: $draft, prompt: Text(".gitignore"))
                .labelsHidden()
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused {
                        commit()
                    }
                }
                .accessibilityIdentifier("ignoreFilenameField")
        } else {
            Text(rows[index])
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard editing == nil, let first = source.first else { return }
        filenames.move(fromOffsets: source, toOffset: destination)
        selection = destination > first ? destination - 1 : destination
    }

    private func barButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private func add() {
        commit()
        draft = ""
        editing = filenames.count
        selection = filenames.count
    }

    private func removeSelected() {
        guard let selection else { return }
        remove(selection)
    }

    private func remove(_ index: Int) {
        if editing != nil {
            cancel()
        }
        selection = nil
        if filenames.indices.contains(index) {
            filenames.remove(at: index)
        }
    }

    private func edit(_ index: Int) {
        commit()
        guard filenames.indices.contains(index) else { return }
        draft = filenames[index]
        editing = index
        selection = index
    }

    private func commit() {
        guard let editing else { return }
        self.editing = nil
        let name = draft.trimmingCharacters(in: .whitespaces)
        if filenames.indices.contains(editing) {
            if name.isEmpty {
                filenames.remove(at: editing)
                selection = nil
            } else {
                filenames[editing] = name
            }
        } else if name.isEmpty {
            selection = nil
        } else {
            filenames.append(name)
        }
    }

    private func cancel() {
        if editing == filenames.count {
            selection = nil
        }
        editing = nil
    }
}
