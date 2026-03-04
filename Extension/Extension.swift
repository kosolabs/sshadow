import Common
import FileProvider
import SwiftData
import SwiftLibSSH
import UniformTypeIdentifiers

public class Extension: NSObject, NSFileProviderReplicatedExtension {
    let logger: Logger
    let manager: SessionManager

    required public init(domain: NSFileProviderDomain) {
        logger = Logger(category: "\(domain.displayName):Extension")

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
        logger.debug("Item \(itemIdentifier.desc)")

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
        logger.debug("Fetch \(itemIdentifier.desc)")

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
        logger.debug(
            "Create \(itemTemplate.desc) for \(fields.desc)"
        )

        var remaining = fields

        let itemIdentifier = itemTemplate.expectedIdentifier
        remaining = remaining.subtracting([.filename, .parentItemIdentifier])

        if itemTemplate.contentType == .folder {
            let subprogress = Progress(totalUnitCount: 1)
            progress.addChild(subprogress, withPendingUnitCount: 1)
            try await session.createDirectory(for: itemIdentifier)
            subprogress.completedUnitCount = 1
        }
        
        if remaining.contains(.contents) {
            let subprogress = Progress(totalUnitCount: 1)
            progress.addChild(subprogress, withPendingUnitCount: 1)
            try await writeFile(
                itemIdentifier,
                basedOn: itemTemplate,
                contents: url,
                progress: subprogress,
                session: session
            )
            remaining = remaining.subtracting([.contents])
        }

        let attrFields: NSFileProviderItemFields = [
            .creationDate, .contentModificationDate, .lastUsedDate,
            .fileSystemFlags, .typeAndCreator,
        ]
        if !remaining.intersection(attrFields).isEmpty {
            let subprogress = Progress(totalUnitCount: 1)
            progress.addChild(subprogress, withPendingUnitCount: 1)
            var changes: [String] = []
            if let at = itemTemplate.lastUsedDate, let accessTime = at {
                changes.append("accessTime: \(accessTime)")
            }
            if let mt = itemTemplate.contentModificationDate,
                let modifyTime = mt
            {
                changes.append("modifyTime: \(modifyTime)")
            }
            if let fileSystemFlags = itemTemplate.fileSystemFlags {
                changes.append("permissions: \(fileSystemFlags.permissions)")
            }
            if let typeAndCreator = itemTemplate.typeAndCreator {
                changes.append("typeAndCreator: \(typeAndCreator)")
            }
            logger.notice(
                "Set attributes of \(itemIdentifier.desc): \(changes.joined(separator: ", "))"
            )
            try await session.setAttributes(
                for: itemIdentifier,
                permissions: itemTemplate.fileSystemFlags?.permissions,
                accessTime: itemTemplate.lastUsedDate ?? nil,
                modifyTime: itemTemplate.contentModificationDate ?? nil,
            )
            remaining = remaining.subtracting(attrFields)
            subprogress.completedUnitCount = 1
        }

        if !remaining.isEmpty {
            logger.fault("Unhandled fields: \(remaining.desc)")
        }
        let item = try await session.item(for: itemIdentifier)
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
            "Modify \(item.desc) for \(changedFields.desc)"
        )

        let itemIdentifier = item.parentItemIdentifier
            .child(name: item.filename)
        var remaining = changedFields

        if remaining.contains(.contents) {
            let subprogress = Progress(totalUnitCount: 1)
            progress.addChild(subprogress, withPendingUnitCount: 1)
            try await writeFile(
                itemIdentifier,
                basedOn: item,
                contents: newContents,
                progress: subprogress,
                session: session
            )
            remaining = remaining.subtracting([.contents])
        }

        let moveFields: NSFileProviderItemFields =
            [.parentItemIdentifier, .filename]
        if !remaining.intersection(moveFields).isEmpty {
            let subprogress = Progress(totalUnitCount: 1)
            progress.addChild(subprogress, withPendingUnitCount: 1)
            logger.notice(
                "Move \(session.path(for: item.itemIdentifier)) to \(session.path(for: itemIdentifier))"
            )
            try await session.move(
                from: item.itemIdentifier,
                to: itemIdentifier
            )
            remaining = remaining.subtracting(moveFields)
            subprogress.completedUnitCount = 1
        }

        let attrFields: NSFileProviderItemFields =
            [.contentModificationDate, .lastUsedDate]
        if !remaining.intersection(attrFields).isEmpty {
            let subprogress = Progress(totalUnitCount: 1)
            progress.addChild(subprogress, withPendingUnitCount: 1)
            if let accessTime = item.lastUsedDate, accessTime != nil {
                logger.notice(
                    "Set access time of \(session.path(for: item.itemIdentifier)) to \(String(describing: accessTime))"
                )
            }
            if let modifyTime = item.contentModificationDate, modifyTime != nil
            {
                logger.notice(
                    "Set modify time of \(session.path(for: item.itemIdentifier)) to \(String(describing: modifyTime))"
                )
            }
            try await session.setAttributes(
                for: itemIdentifier,
                accessTime: item.lastUsedDate ?? nil,
                modifyTime: item.contentModificationDate ?? nil,
            )
            remaining = remaining.subtracting(attrFields)
            subprogress.completedUnitCount = 1
        }

        if !remaining.isEmpty {
            logger.fault("Unhandled fields: \(remaining.desc)")
        }
        let item = try await session.item(for: itemIdentifier)
        return (item, [], false)
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
        logger.debug("Delete \(identifier.desc)")

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
        _ itemIdentifier: NSFileProviderItemIdentifier,
        basedOn itemTemplate: NSFileProviderItem,
        contents url: URL?,
        progress: Progress,
        session: Session,
    ) async throws {
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
    }
}
