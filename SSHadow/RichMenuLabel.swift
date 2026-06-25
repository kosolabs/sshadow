import SwiftUI

struct RichMenuLabel<Icon: View>: View {
    let title: String
    let shortcut: KeyboardShortcut?
    @ViewBuilder let icon: () -> Icon

    init(
        title: String,
        shortcut: KeyboardShortcut? = nil,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.title = title
        self.shortcut = shortcut
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            icon()
                .frame(width: 20, alignment: .center)
            Text(title)
            if let shortcut {
                Spacer()
                Text(display(shortcut))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func display(_ shortcut: KeyboardShortcut) -> String {
        var result = ""
        if shortcut.modifiers.contains(.control) { result += "⌃" }
        if shortcut.modifiers.contains(.option) { result += "⌥" }
        if shortcut.modifiers.contains(.shift) { result += "⇧" }
        if shortcut.modifiers.contains(.command) { result += "⌘" }
        result += String(shortcut.key.character).uppercased()
        return result
    }
}

extension RichMenuLabel where Icon == Image {
    init(
        _ title: String,
        systemImage: String,
        shortcut: KeyboardShortcut? = nil
    ) {
        self.title = title
        self.shortcut = shortcut
        self.icon = { Image(systemName: systemImage) }
    }
}
