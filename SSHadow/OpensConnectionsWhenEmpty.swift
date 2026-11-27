import Common
import CoreKit
import SwiftData
import SwiftUI

private let logger = Logger(category: "OpensConnectionsWhenEmpty")

struct OpensConnectionsWhenEmpty: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            guard hasNoConnections() else { return }
            openWindow.inFront(id: "connections")
            logger.notice("Opened Connections because there are none")
        }
    }

    private func hasNoConnections() -> Bool {
        do {
            return try SSHadowApp.modelContainer.mainContext.fetchCount(
                FetchDescriptor<ConnectionConfigModel>()
            ) == 0
        } catch {
            logger.error("Failed to count connections: \(error)")
            return false
        }
    }
}
