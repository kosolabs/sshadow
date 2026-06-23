import SwiftUI

struct RichMenuLabel<Icon: View>: View {
    let title: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 8) {
            icon()
                .frame(width: 20, alignment: .center)
            Text(title)
        }
    }
}

extension RichMenuLabel where Icon == Image {
    init(_ title: String, systemImage: String) {
        self.title = title
        self.icon = { Image(systemName: systemImage) }
    }
}
