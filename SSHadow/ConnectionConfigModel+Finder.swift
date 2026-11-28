import Common
import CoreKit
import FileProvider

private let logger = Logger(category: "ConnectionConfigModel+Finder")

extension ConnectionConfigModel {
    func resolveFolderUrl() async -> URL? {
        guard isEnabled() else { return nil }
        do {
            return try await domain.manager.getUserVisibleURL(
                for: .rootContainer
            )
        } catch {
            logger.error("Failed to resolve URL for \(self): \(error)")
            return nil
        }
    }
}
