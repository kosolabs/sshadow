import SwiftUI

extension View {
    @MainActor
    func rasterized(scale: CGFloat, isTemplate: Bool) -> Image {
        let renderer = ImageRenderer(content: self)
        renderer.scale = scale

        guard let nsImage = renderer.nsImage else {
            return Image(systemName: "exclamationmark.triangle")
        }
        nsImage.isTemplate = isTemplate
        return Image(nsImage: nsImage)
    }

    @ViewBuilder
    func draggable<T: Transferable>(ifAvailable payload: T?) -> some View {
        if let payload {
            draggable(payload)
        } else {
            self
        }
    }

    func menuHighlight(_ isHighlighted: Bool) -> some View {
        background(
            isHighlighted
                ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
