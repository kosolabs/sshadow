import CoreKit
import Foundation
import SwiftData

@Observable
final class SettingsNavigation {
    var selectedConfig: ConnectionConfigModel?

    func addConnection(to modelContext: ModelContext) {
        let config = ConnectionConfigModel()
        modelContext.insert(config)
        selectedConfig = config
    }
}
