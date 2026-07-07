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
}
