import CoreKit
import Foundation
import SwiftData

@Observable
final class SettingsNavigation {
    var section: SettingsSection? = .connections
    var selectedConfig: ConnectionConfigModel?

    func show(_ config: ConnectionConfigModel) {
        section = .connections
        selectedConfig = config
    }

    func addConnection(to modelContext: ModelContext) {
        let config = ConnectionConfigModel()
        modelContext.insert(config)
        show(config)
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case connections
    case general
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .connections: "Connections"
        case .general: "General"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .connections: "externaldrive.badge.icloud"
        case .general: "gearshape"
        case .advanced: "gearshape.2"
        }
    }
}
