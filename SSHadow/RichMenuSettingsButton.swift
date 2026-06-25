import Common
import Foundation
import SwiftData
import SwiftUI

struct RichMenuSettingsButton<Content: View>: View {
    @ViewBuilder let label: () -> Content

    @State private var isHovered = false

    var body: some View {
        SettingsLink {
            HStack {
                label()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8).fill(
                    isHovered ? Color.primary : Color.clear
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            TapGesture().onEnded {
                NSApp.dismissMenuBarExtra()
                NSApp.activate()
            }
        )
    }
}
