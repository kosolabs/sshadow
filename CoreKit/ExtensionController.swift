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

extension ExtensionController {
    func suspend(reason: String) async {
        await suspend(reason: reason, options: [])
    }
}

extension NSFileProviderDomain: ExtensionController {}
