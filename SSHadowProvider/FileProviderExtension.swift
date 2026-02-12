import FileProvider
import OSLog
import SSHadowShared
import SwiftData
import SwiftLibSSH

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let logger: Logger
    private let config: ConnectionConfig?

    required init(domain: NSFileProviderDomain) {
        // TODO: The containing application must create a domain using `NSFileProviderManager.add(_:, completionHandler:)`. The system will then launch the application extension process, call `FileProviderExtension.init(domain:)` to instantiate the extension for that domain, and call methods on the instance.
        logger = getLogger(
            category: "Extension.\(domain.displayName)"
        )

        if let userInfo = try? UserInfo.fromDictionary(domain.userInfo),
            let config = try? ConnectionConfig(from: userInfo)
        {
            self.config = config
            logger.debug("init: \(config, privacy: .public)")
        } else {
            self.config = nil
            logger.fault("Failed to retrieve connection config")
        }

        super.init()
    }

    func invalidate() {
        // TODO: cleanup any resources
    }

    func item(
        for itemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        // resolve the given identifier to a record in the model

        // TODO: implement the actual lookup

        logger.debug("item: \(itemIdentifier.rawValue, privacy: .public)")
        let progress = Progress()

        Task {
            do {
                let item = try await item(
                    for: itemIdentifier,
                    request: request,
                    progress: progress
                )
                completionHandler(item, nil)
            } catch {
                completionHandler(nil, error)
            }
        }

        return progress
    }

    private func item(
        for itemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        progress: Progress,
    ) async throws -> NSFileProviderItem {
        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }

        if itemIdentifier == .rootContainer
            || itemIdentifier == .trashContainer
            || itemIdentifier == .workingSet
        {
            return FileProviderSpecialItem(
                domainName: config.name,
                itemIdentifier: itemIdentifier
            )
        }

        let attrs = try await SSHClient.withSession(config: config) { _, sftp in
            try await sftp.attributes(atPath: itemIdentifier.rawValue)
        }

        return FileProviderItem(
            domainName: config.name,
            itemIdentifier: itemIdentifier,
            itemAttributes: attrs
        )
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
            itemIdentifier: containerItemIdentifier
        )
    }
}
