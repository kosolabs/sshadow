import Common
import FileProvider
import OSLog
import SwiftData
import SwiftLibSSH
import UniformTypeIdentifiers

public class Extension: NSObject, NSFileProviderReplicatedExtension {
    let logger: Logger
    let config: ConnectionConfig?

    required public init(domain: NSFileProviderDomain) {
        logger = getLogger(category: "Extension.\(domain.displayName)")

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
                completionHandler(nil, remap(error: error))
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

        logger.debug(
            "Item: \(config.path(for: itemIdentifier), privacy: .public)"
        )

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
            try await sftp.attributes(atPath: config.path(for: itemIdentifier))
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

    private func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        progress: Progress,
    ) async throws -> (URL, NSFileProviderItem) {
        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }
        logger.debug(
            "fetch: \(config.path(for: itemIdentifier), privacy: .public)"
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
                progress.totalUnitCount = Int64(attrs.size)
                for try await data in file.stream() {
                    if progress.isCancelled {
                        throw CocoaError(.userCancelled)
                    }
                    try handle.write(contentsOf: data)
                    progress.completedUnitCount += Int64(data.count)
                }
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

        //        completionHandler(itemTemplate, [], false, nil)
        let progress = Progress()

        Task {
            do {
                let (item, fields, bool) = try await createItem(
                    basedOn: itemTemplate,
                    fields: fields,
                    contents: url,
                    options: options,
                    request: request,
                    progress: progress
                )
                completionHandler(item, fields, bool, nil)
            } catch {
                logger.error(
                    """
                    Failed to create item for \
                    \(itemTemplate.filename, privacy: .public): \
                    \(error, privacy: .public)
                    """
                )
                completionHandler(nil, [], false, remap(error: error))
            }
        }

        return Progress()
    }

    private func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
    ) async throws -> (NSFileProviderItem, NSFileProviderItemFields, Bool) {
        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }
        logger.debug(
            "create item (\(type(of: itemTemplate), privacy: .public)): \(itemTemplate.description, privacy: .public)"
        )
        logItem(item: itemTemplate, fields: fields)

        let itemIdentifier = itemTemplate.parentItemIdentifier
            .child(name: itemTemplate.filename)
        let remotePath = config.path(for: itemIdentifier)

        let item = try await SSHClient.withSession(config: config) { _, sftp in
            if itemTemplate.contentType == .folder {
                progress.totalUnitCount = 1
                logger.debug(
                    "create folder: \(remotePath, privacy: .public)"
                )
                try await sftp.createDirectory(atPath: remotePath)
                let attrs = try await sftp.attributes(atPath: remotePath)
                progress.completedUnitCount = 1
                return Item(
                    domainName: config.name,
                    itemIdentifier: itemIdentifier,
                    itemAttributes: attrs
                )
            }

            guard let url = url,
                let documentSize = itemTemplate.documentSize,
                let documentSize = documentSize
            else {
                logger.error(
                    """
                    Missing contents URL or document size for \
                    \(itemTemplate.filename, privacy: .public)
                    """
                )
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            progress.totalUnitCount = Int64(truncating: documentSize)

            let fp = try FileHandle(forReadingFrom: url)
            defer { try? fp.close() }

            try await sftp.withSftpFile(
                atPath: remotePath,
                accessType: .writeOnly
            ) { file in
                try await file.withAsyncWriter { writer in
                    while let data = try fp.read(upToCount: 102400) {
                        if progress.isCancelled {
                            throw CocoaError(.userCancelled)
                        }
                        try await writer.write(data: data)
                        progress.completedUnitCount += Int64(data.count)
                    }
                }
            }
            let attrs = try await sftp.attributes(atPath: remotePath)
            return Item(
                domainName: config.name,
                itemIdentifier: itemIdentifier,
                itemAttributes: attrs
            )
        }

        return (item, [], false)
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
        let progress = Progress()

        Task {
            do {
                try await deleteItem(
                    identifier: identifier,
                    baseVersion: version,
                    options: options,
                    request: request,
                    progress: progress
                )
                completionHandler(nil)
            } catch {
                logger.error(
                    """
                    Failed to delete item \
                    \(identifier.rawValue, privacy: .public): \
                    \(error, privacy: .public)
                    """
                )
                completionHandler(remap(error: error))
            }
        }

        return progress
    }

    private func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
    ) async throws {
        guard let config = self.config else {
            throw NSFileProviderError(.notAuthenticated)
        }
        logger.debug(
            "delete item: \(config.path(for: identifier), privacy: .public)"
        )

        try await SSHClient.withSession(config: config) { _, sftp in
            let attrs = try await sftp.attributes(
                atPath: config.path(for: identifier)
            )
            progress.totalUnitCount = 1
            if case .directory = attrs.type {
                try await sftp.removeDirectory(
                    atPath: config.path(for: identifier)
                )
            } else {
                try await sftp.removeFile(atPath: config.path(for: identifier))
            }
            progress.completedUnitCount = 1
        }
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

    private func logItem(
        item: NSFileProviderItem,
        fields: NSFileProviderItemFields
    ) {
        let allFields: [(NSFileProviderItemFields, String, Any?)] = [
            (
                .filename, "filename", item.filename
            ),
            (
                .parentItemIdentifier, "parentItemIdentifier",
                item.parentItemIdentifier
            ),
            (
                .lastUsedDate, "lastUsedDate", item.lastUsedDate as Any?
            ),
            (
                .tagData, "tagData", item.tagData as Any?
            ),
            (
                .creationDate, "creationDate", item.creationDate as Any?
            ),
            (
                .contentModificationDate, "contentModificationDate",
                item.contentModificationDate as Any?
            ),
            (
                .fileSystemFlags, "fileSystemFlags", item.fileSystemFlags
            ),
            (
                .extendedAttributes, "extendedAttributes",
                item.extendedAttributes
            ),
            (
                .typeAndCreator, "typeAndCreator", item.typeAndCreator
            ),
        ]

        for (field, name, value) in allFields where fields.contains(field) {
            logger.debug(
                """
                Field \
                \(name, privacy: .public): \
                \(String(describing: value), privacy: .public)
                """
            )
        }
        logger.debug(
            """
            Field contentType: \
            \(String(describing: item.contentType), privacy: .public)
            """
        )
        logger.debug(
            """
            Field documentSize: \
            \(String(describing: item.documentSize), privacy: .public)
            """
        )
    }
}
