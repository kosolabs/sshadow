import Common
import FileProvider
import SwiftData
import SwiftLibSSH
import UniformTypeIdentifiers

public class Extension: NSObject, NSFileProviderReplicatedExtension {
    let logger: Logger
    let config: ConnectionConfig?

    required public init(domain: NSFileProviderDomain) {
        logger = Logger(category: "Extension.\(domain.displayName)")

        if let userInfo = try? UserInfo.fromDictionary(domain.userInfo),
            let config = try? ConnectionConfig(from: userInfo)
        {
            self.config = config
            logger.debug("init: \(config)")
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
            guard let config = self.config else {
                return completionHandler(
                    nil,
                    NSFileProviderError(.notAuthenticated)
                )
            }

            logger.debug("Get item: \(config.path(for: itemIdentifier))")
            do {
                let item = try await item(
                    for: itemIdentifier,
                    request: request,
                    progress: progress,
                    config: config,
                )
                logger.notice("Got item: \(item.description)")
                completionHandler(item, nil)
            } catch {
                if let sshError = error as? SSHError,
                    case .sftpError(let sftpError, _) = sshError,
                    sftpError == .noSuchFile
                {
                    logger.notice(
                        "No such item: \(config.path(for: itemIdentifier))"
                    )
                } else {
                    logger.fault(
                        "Failed to get item \(itemIdentifier.rawValue): \(error)"
                    )
                }
                completionHandler(nil, remap(error: error))
            }
        }

        return progress
    }

    private func item(
        for itemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        progress: Progress,
        config: ConnectionConfig,
    ) async throws -> NSFileProviderItem {
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
            guard let config = self.config else {
                return completionHandler(
                    nil,
                    nil,
                    NSFileProviderError(.notAuthenticated)
                )
            }

            do {
                let (url, item) = try await fetchContents(
                    for: itemIdentifier,
                    version: requestedVersion,
                    request: request,
                    progress: progress,
                    config: config,
                )
                completionHandler(url, item, nil)
            } catch {
                logger.fault(
                    "Failed to fetch contents of \(itemIdentifier.rawValue): \(error)"
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
        config: ConnectionConfig,
    ) async throws -> (URL, NSFileProviderItem) {
        logger.debug(
            """
            Fetch contents: \
            \(config.path(for: itemIdentifier))
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
        let progress = Progress()

        Task {
            guard let config = self.config else {
                return completionHandler(
                    nil,
                    [],
                    false,
                    NSFileProviderError(.notAuthenticated)
                )
            }

            do {
                let (item, fields, bool) = try await createItem(
                    basedOn: itemTemplate,
                    fields: fields,
                    contents: url,
                    options: options,
                    request: request,
                    progress: progress,
                    config: config,
                )
                completionHandler(item, fields, bool, nil)
            } catch {
                logger.fault(
                    "Failed to create item \(itemTemplate.filename): \(error)"
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
        config: ConnectionConfig,
    ) async throws -> (NSFileProviderItem, NSFileProviderItemFields, Bool) {
        logger.debug("Create item: \(itemTemplate.description)")
        logItem(item: itemTemplate, fields: fields)

        let itemIdentifier = itemTemplate.parentItemIdentifier
            .child(name: itemTemplate.filename)
        let remotePath = config.path(for: itemIdentifier)

        let item = try await SSHClient.withSession(config: config) { _, sftp in
            // TODO: Set create and modify timestamps
            if itemTemplate.contentType == .folder {
                progress.totalUnitCount = 1
                logger.debug("create folder: \(remotePath)")
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
                logger.fault(
                    "Missing contents URL or document size for \(itemTemplate.filename)"
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
        let progress = Progress()

        Task {
            guard let config = self.config else {
                return completionHandler(
                    nil,
                    [],
                    false,
                    NSFileProviderError(.notAuthenticated)
                )
            }
            logger.debug(
                "Modify \(config.path(for: item.itemIdentifier)) \(item.description)"
            )
            do {
                let (item, fields, bool) = try await modifyItem(
                    item,
                    baseVersion: version,
                    changedFields: changedFields,
                    contents: newContents,
                    options: options,
                    request: request,
                    progress: progress,
                    config: config,
                )
                completionHandler(item, fields, bool, nil)
            } catch {
                logger.fault(
                    "Failed to modify item \(item.filename): \(error)"
                )
                completionHandler(nil, [], false, remap(error: error))
            }
        }

        return Progress()
    }

    private func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
        config: ConnectionConfig,
    ) async throws -> (NSFileProviderItem?, NSFileProviderItemFields, Bool) {
        let moveFields: NSFileProviderItemFields =
            [.parentItemIdentifier, .filename]
        logItem(item: item, fields: changedFields)

        if !changedFields.intersection(moveFields).isEmpty {
            let fromItemID = item.itemIdentifier
            let toItemID = item.parentItemIdentifier.child(name: item.filename)
            logger.notice(
                "Move \(config.path(for: fromItemID)) to \(config.path(for: toItemID))"
            )
            let item = try await SSHClient.withSession(config: config) {
                _,
                sftp in
                progress.totalUnitCount = 1
                try await sftp.move(
                    from: config.path(for: fromItemID),
                    to: config.path(for: toItemID)
                )
                let attrs = try await sftp.attributes(
                    atPath: config.path(for: toItemID)
                )
                progress.completedUnitCount = 1
                return Item(
                    domainName: config.name,
                    itemIdentifier: toItemID,
                    itemAttributes: attrs
                )
            }

            let remaining = changedFields.subtracting(moveFields)
            if !remaining.isEmpty {
                logger.error("Remaining fields: \(remaining)")
            }
            return (item, remaining, false)
        }

        if changedFields.contains(.contentModificationDate),
            let modifyTime = item.contentModificationDate
        {
            logger.notice(
                "Set modify time of \(config.path(for: item.itemIdentifier)) to \(String(describing: modifyTime))"
            )
            try await SSHClient.withSession(config: config) {
                _,
                sftp in
                try await sftp.setAttributes(
                    atPath: config.path(for: item.itemIdentifier),
                    modifyTime: modifyTime
                )
            }

            let remaining = changedFields.subtracting([.contentModificationDate]
            )
            if !remaining.isEmpty {
                logger.error("Remaining fields: \(remaining)")
            }
            return (item, remaining, false)
        }

        if changedFields.contains(.lastUsedDate),
            let accessTime = item.lastUsedDate
        {
            logger.notice(
                "Set access time of \(config.path(for: item.itemIdentifier)) to \(String(describing: accessTime))"
            )
            try await SSHClient.withSession(config: config) {
                _,
                sftp in
                try await sftp.setAttributes(
                    atPath: config.path(for: item.itemIdentifier),
                    accessTime: accessTime
                )
            }

            let remaining = changedFields.subtracting([.lastUsedDate]
            )
            if !remaining.isEmpty {
                logger.error("Remaining fields: \(remaining)")
            }
            return (item, remaining, false)
        }

        logger.fault("Unhandled fields: \(changedFields)")

        throw CocoaError(.featureUnsupported)
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
            guard let config = self.config else {
                return completionHandler(NSFileProviderError(.notAuthenticated))
            }
            do {
                try await deleteItem(
                    identifier: identifier,
                    baseVersion: version,
                    options: options,
                    request: request,
                    progress: progress,
                    config: config,
                )
                completionHandler(nil)
            } catch {
                logger.fault(
                    "Failed to delete item \(identifier.rawValue): \(error)"
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
        config: ConnectionConfig,
    ) async throws {
        logger.debug(
            "delete item: \(config.path(for: identifier))"
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
            \(name): \
            \(String(describing: value))
            """
        )
    }
}
