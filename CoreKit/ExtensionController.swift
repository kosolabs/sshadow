import Common
import FileProvider

protocol ExtensionController {
    func resume() async
    func suspend(
        reason: String,
        options: NSFileProviderManager.DisconnectionOptions
    ) async
    func remove() async
}

extension NSFileProviderDomain: ExtensionController {}
