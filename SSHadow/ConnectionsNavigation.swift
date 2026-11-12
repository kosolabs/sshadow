import Common
import CoreKit
import Foundation
import SwiftData

private let logger = Logger(category: "ConnectionsNavigation")

@Observable
final class ConnectionsNavigation {
    var selectedConfig: ConnectionConfigModel?

    func addConnection(to modelContext: ModelContext) {
        let config = ConnectionConfigModel()
        modelContext.insert(config)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save new connection: \(error)")
        }
        selectedConfig = config
    }
}
