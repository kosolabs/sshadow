import Common
import SwiftUI

private let logger = Logger(category: "OpensRequestedWindows")

struct OpensRequestedWindows: ViewModifier {
    private static let notification = Notification.Name(
        "com.kosolabs.SSHadow.openWindowRequested"
    )

    @Environment(\.openWindow) private var openWindow

    static func request(id: String) {
        NotificationCenter.default.post(name: notification, object: id)
    }

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: Self.notification)
        ) { notification in
            guard let id = notification.object as? String else { return }
            openWindow.inFront(id: id)
            logger.notice("Opened window: \(id)")
        }
    }
}
