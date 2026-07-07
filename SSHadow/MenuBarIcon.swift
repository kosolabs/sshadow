import SwiftUI

struct MenuBarIcon: View {
    var isLoading: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var angle: Int = 0

    private let fps: Double = 30

    var body: some View {
        Image(isLoading ? "sshadow.badge.base" : "sshadow.badge.cloud")
            .resizable()
            .scaledToFit()
            .overlay(alignment: .bottomLeading) {
                if isLoading {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 9, height: 9)
                        .rotationEffect(.degrees(Double(angle)))
                }
            }
        .frame(width: 18, height: 18)
        .rasterized(scale: displayScale, isTemplate: true)
        .task(id: isLoading) {
            guard isLoading else { return }
            let step = Int(360 / fps)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1 / fps))
                angle = (angle + step) % 360
            }
        }
    }
}
