import FileProvider
import OSLog
import SSHadowShared
import SwiftData
import SwiftLibSSH

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "FileProviderExtension"
)

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let config: ConnectionConfig?

    required init(domain: NSFileProviderDomain) {
        // TODO: The containing application must create a domain using `NSFileProviderManager.add(_:, completionHandler:)`. The system will then launch the application extension process, call `FileProviderExtension.init(domain:)` to instantiate the extension for that domain, and call methods on the instance.
        logger.debug(
            "init: \(domain.displayName, privacy: .public) (\(domain.identifier.rawValue, privacy: .public))"
        )

        if let userInfo = domain.userInfo,
            let json = userInfo["connectionConfig"] as? String,
            let config = ConnectionConfig.fromJSON(json)
        {
            self.config = config
        } else {
            logger.fault("Failed to retrieve connection config")
            self.config = nil
        }
        
        do {
            let password = try Keychain().get("password.\(domain.identifier.rawValue)")?.decoded(as: .utf8)
            logger.info("password: \(password ?? "nil", privacy: .public)")
        } catch {
            logger.error("error: \(error)")
        }

        super.init()
    }

    func invalidate() {
        logger.debug("invalidate")
        // TODO: cleanup any resources
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        // resolve the given identifier to a record in the model

        // TODO: implement the actual lookup

        completionHandler(FileProviderItem(identifier: identifier), nil)
        return Progress()
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        // TODO: implement fetching of the contents for the itemIdentifier at the specified version

        completionHandler(
            nil,
            nil,
            NSError(
                domain: NSCocoaErrorDomain,
                code: NSFeatureUnsupportedError,
                userInfo: [:]
            )
        )
        return Progress()
    }

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler:
            @escaping (
                NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?
            ) -> Void
    ) -> Progress {
        // TODO: a new item was created on disk, process the item's creation

        completionHandler(itemTemplate, [], false, nil)
        return Progress()
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler:
            @escaping (
                NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?
            ) -> Void
    ) -> Progress {
        // TODO: an item was modified on disk, process the item's modification

        completionHandler(
            nil,
            [],
            false,
            NSError(
                domain: NSCocoaErrorDomain,
                code: NSFeatureUnsupportedError,
                userInfo: [:]
            )
        )
        return Progress()
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        // TODO: an item was deleted on disk, process the item's deletion

        completionHandler(
            NSError(
                domain: NSCocoaErrorDomain,
                code: NSFeatureUnsupportedError,
                userInfo: [:]
            )
        )
        return Progress()
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }

        return FileProviderEnumerator(
            config: config,
            enumeratedItemIdentifier: containerItemIdentifier
        )
    }
}
