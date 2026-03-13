import Common
import FileProvider

extension ConnectionConfig {
    public func path(
        for itemIdentifier: NSFileProviderItemIdentifier
    ) -> String {
        path(for: itemIdentifier.path)
    }
}
