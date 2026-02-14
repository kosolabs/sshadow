import Common
import FileProvider
import OSLog
import SwiftData
import SwiftLibSSH

public class Extension: NSObject, NSFileProviderReplicatedExtension {
    let logger: Logger
    let config: ConnectionConfig?

    required public init(domain: NSFileProviderDomain) {
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

    public func invalidate() {
        // TODO: cleanup any resources
    }

    public func item(
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

    func item(
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
            return SpecialItem(
                domainName: config.name,
                itemIdentifier: itemIdentifier
            )
        }

        let attrs = try await SSHClient.withSession(config: config) { _, sftp in
            try await sftp.attributes(atPath: itemIdentifier.rawValue)
        }

        return Item(
            domainName: config.name,
            itemIdentifier: itemIdentifier,
            itemAttributes: attrs
        )
    }

    public func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        // TODO: implement fetching of the contents for the itemIdentifier at the specified version

        logger.debug(
            "fetchContents: \(itemIdentifier.rawValue, privacy: .public)"
        )
        let progress = Progress()

        Task {
            do {
                let (url, item) = try await fetchContents(
                    for: itemIdentifier,
                    version: requestedVersion,
                    request: request,
                    progress: progress
                )
                completionHandler(url, item, nil)
            } catch {
                logger.error(
                    """
                    Failed to fetch contents of \
                    \(itemIdentifier.rawValue, privacy: .public): \
                    \(error, privacy: .public)
                    """
                )
                completionHandler(nil, nil, error)
            }
        }

        return progress
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        progress: Progress,
    ) async throws -> (URL, NSFileProviderItem) {
        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }
        logger.debug(
            """
            Fetching contents of \
            \(config.path(for: itemIdentifier.rawValue), privacy: .public)
            """
        )

        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path(), contents: nil)
        else {
            throw NSFileProviderError(.insufficientQuota)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let attrs = try await SSHClient.withSession(config: config) { _, sftp in
            try await sftp.withSftpFile(
                atPath: config.path(for: itemIdentifier),
                accessType: .readOnly
            ) { file in
                let attrs = try await file.attributes()
                logger.debug("fetching \(attrs.size) bytes")
                progress.totalUnitCount = Int64(attrs.size)
                for try await data in file.stream() {
                    logger.debug("fetched \(data.count) bytes")
                    if progress.isCancelled {
                        throw CocoaError(.userCancelled)
                    }
                    try handle.write(contentsOf: data)
                    progress.completedUnitCount += Int64(data.count)
                }
                logger.debug("finished fetching")
                return attrs
            }
        }

        return (
            url,
            Item(
                domainName: config.name,
                itemIdentifier: itemIdentifier,
                itemAttributes: attrs
            )
        )
    }

    public func createItem(
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

    public func modifyItem(
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

    public func deleteItem(
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

    public func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }

        return Enumerator(
            config: config,
            itemIdentifier: containerItemIdentifier
        )
    }
}
