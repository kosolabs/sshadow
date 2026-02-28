import Common
import FileProvider
import SwiftData
import SwiftLibSSH
import UniformTypeIdentifiers

public class Extension: NSObject, NSFileProviderReplicatedExtension {
    let logger: Logger
    let manager: SessionManager

    required public init(domain: NSFileProviderDomain) {
        logger = Logger(category: "Extension.\(domain.displayName)")

        do {
            let userInfo = try UserInfo.fromDictionary(domain.userInfo)
            let config = try ConnectionConfig(from: userInfo)
            manager = SessionManager(name: domain.displayName, config: config)
            logger.debug("init: \(config)")
        } catch {
            manager = SessionManager(name: domain.displayName, config: nil)
            logger.fault("Failed to retrieve connection config: \(error)")
        }

        super.init()
    }

    public func invalidate() {
        Task {
            await manager.close()
        }
    }

    public func item(
        for itemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        manager.withSession { session, progress in
            try await self.item(
                for: itemIdentifier,
                request: request,
                progress: progress,
                session: session,
            )
        } onSuccess: { item in
            completionHandler(item, nil)
        } onError: { error in
            completionHandler(nil, error)
        }
    }

    func item(
        for itemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        progress: Progress,
        session: Session,
    ) async throws -> NSFileProviderItem {
        logger.debug("Get item: \(session.path(for: itemIdentifier))")

        if itemIdentifier == .rootContainer
            || itemIdentifier == .trashContainer
            || itemIdentifier == .workingSet
        {
            return SpecialItem(
                domainName: session.config.name,
                itemIdentifier: itemIdentifier
            )
        }

        return try await session.item(for: itemIdentifier)
    }

    public func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        manager.withSession { session, progress in
            try await self.fetchContents(
                for: itemIdentifier,
                version: requestedVersion,
                request: request,
                progress: progress,
                session: session,
            )
        } onSuccess: { url, item in
            completionHandler(url, item, nil)
        } onError: { error in
            self.logger.fault(
                "Failed to fetch contents of \(itemIdentifier)"
            )
            completionHandler(nil, nil, error)
        }
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        progress: Progress,
        session: Session,
    ) async throws -> (URL, NSFileProviderItem) {
        logger.debug("Fetch contents: \(session.path(for: itemIdentifier))")

        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path(), contents: nil)
        else {
            throw NSFileProviderError(.insufficientQuota)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let item = try await session.item(for: itemIdentifier)
        progress.totalUnitCount = Int64(item.size)

        try await session.withFile(
            for: itemIdentifier,
            accessType: .readOnly
        ) { file in
            for try await data in file.stream() {
                if progress.isCancelled {
                    throw CocoaError(.userCancelled)
                }
                try handle.write(contentsOf: data)
                progress.completedUnitCount += Int64(data.count)
            }
        }

        return (url, item)
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
        manager.withSession { session, progress in
            try await self.createItem(
                basedOn: itemTemplate,
                fields: fields,
                contents: url,
                options: options,
                request: request,
                progress: progress,
                session: session,
            )
        } onSuccess: { item, fields, shouldFetchContent in
            completionHandler(item, fields, shouldFetchContent, nil)
        } onError: { error in
            self.logger.fault(
                "Failed to create item \(itemTemplate.itemIdentifier)"
            )
            completionHandler(nil, [], false, error)
        }
    }

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
        session: Session,
    ) async throws -> (NSFileProviderItem, NSFileProviderItemFields, Bool) {
        logger.debug("Create item: \(itemTemplate.description)")
        logItem(item: itemTemplate, fields: fields)

        let itemIdentifier = itemTemplate.parentItemIdentifier
            .child(name: itemTemplate.filename)
        
        if itemTemplate.contentType != .folder {
            let item = try await writeFile(
                basedOn: itemTemplate,
                contents: url,
                progress: progress,
                session: session
            )

            return (item, [], false)
        }

        // TODO: Set create and modify timestamps
        progress.totalUnitCount = 1
        try await session.createDirectory(for: itemIdentifier)
        let item = try await session.item(for: itemIdentifier)
        progress.completedUnitCount = 1
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
        manager.withSession { session, progress in
            try await self.modifyItem(
                item,
                baseVersion: version,
                changedFields: changedFields,
                contents: newContents,
                options: options,
                request: request,
                progress: progress,
                session: session,
            )
        } onSuccess: { item, fields, shouldFetchContent in
            completionHandler(item, fields, shouldFetchContent, nil)
        } onError: { error in
            self.logger.fault(
                "Failed to modify item \(item.itemIdentifier)"
            )
            completionHandler(nil, [], false, error)
        }
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
        session: Session,
    ) async throws -> (NSFileProviderItem?, NSFileProviderItemFields, Bool) {
        logger.debug(
            "Modify \(session.path(for: item.itemIdentifier)) \(item.description)"
        )

        let moveFields: NSFileProviderItemFields =
            [.parentItemIdentifier, .filename]
        logItem(item: item, fields: changedFields)

        if changedFields.contains(.contents) {
            let item = try await writeFile(
                basedOn: item,
                contents: newContents,
                progress: progress,
                session: session
            )

            let remaining = changedFields.subtracting([.contents])
            if !remaining.isEmpty {
                logger.error("Remaining fields: \(remaining)")
            }
            return (item, remaining, false)
        }

        if !changedFields.intersection(moveFields).isEmpty {
            let fromItemID = item.itemIdentifier
            let toItemID = item.parentItemIdentifier.child(name: item.filename)
            logger.notice(
                "Move \(session.path(for: fromItemID)) to \(session.path(for: toItemID))"
            )
            progress.totalUnitCount = 1
            try await session.move(from: fromItemID, to: toItemID)
            let item = try await session.item(for: toItemID)
            progress.completedUnitCount = 1

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
                "Set modify time of \(session.path(for: item.itemIdentifier)) to \(String(describing: modifyTime))"
            )
            try await session.setAttributes(
                for: item.itemIdentifier,
                modifyTime: modifyTime
            )

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
                "Set access time of \(session.path(for: item.itemIdentifier)) to \(String(describing: accessTime))"
            )
            try await session.setAttributes(
                for: item.itemIdentifier,
                accessTime: accessTime
            )

            let remaining = changedFields.subtracting([.lastUsedDate])
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
        manager.withSession { session, progress in
            try await self.deleteItem(
                identifier: identifier,
                baseVersion: version,
                options: options,
                request: request,
                progress: progress,
                session: session,
            )
        } onSuccess: {
            completionHandler(nil)
        } onError: { error in
            self.logger.fault(
                "Failed to delete item \(identifier)"
            )
            completionHandler(error)
        }
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
        session: Session,
    ) async throws {
        logger.debug("delete item: \(session.path(for: identifier))")

        progress.totalUnitCount = 1
        let attrs = try await session.attributes(for: identifier)
        if case .directory = attrs.type {
            try await session.removeDirectory(for: identifier)
        } else {
            try await session.removeFile(for: identifier)
        }
        progress.completedUnitCount = 1
    }

    public func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        return Enumerator(
            manager: manager,
            itemIdentifier: containerItemIdentifier
        )
    }

    private func writeFile(
        basedOn itemTemplate: NSFileProviderItem,
        contents url: URL?,
        progress: Progress,
        session: Session,
    ) async throws -> Item {
        let itemIdentifier = itemTemplate.parentItemIdentifier
            .child(name: itemTemplate.filename)

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

        try await session.withFile(
            for: itemIdentifier,
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

        return try await session.item(for: itemIdentifier)
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

}
