import Common
import FileProvider
import SwiftData
import SwiftLibSSH
import UniformTypeIdentifiers

public class Extension: NSObject, NSFileProviderReplicatedExtension,
    NSFileProviderPartialContentFetching
{
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

        return try await progress.withChild {
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
        let (url, item, _) = try await read(
            itemIdentifier,
            progress: progress,
            session: session
        )
        return (url, item)
    }

    public func fetchPartialContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion,
        request: NSFileProviderRequest,
        minimalRange range: NSRange,
        aligningTo alignment: Int,
        options: NSFileProviderFetchContentsOptions = [],
        completionHandler:
            @escaping (
                URL?, NSFileProviderItem?, NSRange,
                NSFileProviderMaterializationFlags, (any Error)?
            ) -> Void
    ) -> Progress {
        manager.withSession { session, progress in
            try await self.fetchPartialContents(
                for: itemIdentifier,
                version: requestedVersion,
                request: request,
                minimalRange: range,
                aligningTo: alignment,
                options: options,
                progress: progress,
                session: session
            )
        } onSuccess: { url, item, range in
            completionHandler(url, item, range, [], nil)
        } onError: { error in
            completionHandler(nil, nil, range, [], error)
        }
    }

    func fetchPartialContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion,
        request: NSFileProviderRequest,
        minimalRange range: NSRange,
        aligningTo alignment: Int,
        options: NSFileProviderFetchContentsOptions = [],
        progress: Progress,
        session: Session,
    ) async throws -> (URL, NSFileProviderItem, NSRange) {
        logger.debug(
            """
            Fetch partial contents of \(itemIdentifier.desc) \
            with range(\(range.location), \(range.length)) \
            aligned to \(alignment)
            """
        )

        return try await read(
            itemIdentifier,
            range: range.aligned(to: alignment),
            progress: progress,
            session: session
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
        basedOn item: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
        session: Session,
    ) async throws -> (NSFileProviderItem, NSFileProviderItemFields, Bool) {
        logger.debug(
            "Create \(item.desc) for \(fields.desc)"
        )

        let itemIdentifier = item.expectedIdentifier
        var remaining = fields.subtracting(.nameFields)
        progress.totalUnitCount =
            (2 + (remaining.intersects(with: .attrFields) ? 1 : 0))

        if remaining.intersects(with: .writeFields) {
            let fileSystemFlags =
                remaining.contains(.fileSystemFlags)
                ? item.fileSystemFlags ?? [] : []
            remaining = remaining.subtracting([.fileSystemFlags])

            try await progress.withChild { subprogress in
                try await write(
                    itemIdentifier,
                    basedOn: item,
                    contents: url,
                    fileSystemFlags: fileSystemFlags,
                    progress: subprogress,
                    session: session
                )
                remaining = remaining.subtracting(.writeFields)
            }
        } else if item.contentType == .folder {
            try await progress.withChild {
                try await session.createDirectory(for: itemIdentifier)
            }
        }

        if remaining.intersects(with: .attrFields) {
            try await progress.withChild {
                try await setAttributes(
                    item,
                    fields: fields,
                    session: session
                )
                remaining = remaining.subtracting(.attrFields)
            }
        }

        if !remaining.isEmpty {
            logger.fault("Unhandled fields: \(remaining.desc)")
        }
        let item = try await progress.withChild {
            try await session.item(for: itemIdentifier)
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

        let itemIdentifier = item.expectedIdentifier
        var remaining = changedFields
        progress.totalUnitCount =
            (1 + (remaining.intersects(with: .writeFields) ? 1 : 0)
                + (remaining.intersects(with: .nameFields) ? 1 : 0)
                + (remaining.intersects(with: .attrFields) ? 1 : 0))

        if remaining.intersects(with: .writeFields) {
            let fileSystemFlags =
                remaining.contains(.fileSystemFlags)
                ? item.fileSystemFlags ?? [] : []
            remaining = remaining.subtracting([.fileSystemFlags])

            try await progress.withChild { subprogress in
                try await write(
                    itemIdentifier,
                    basedOn: item,
                    contents: newContents,
                    fileSystemFlags: fileSystemFlags,
                    progress: subprogress,
                    session: session
                )
                remaining = remaining.subtracting(.writeFields)
            }
        }

        if remaining.intersects(with: .nameFields) {
            try await progress.withChild {
                logger.notice(
                    "Move \(session.path(for: item.itemIdentifier)) to \(session.path(for: itemIdentifier))"
                )
                try await session.move(
                    from: item.itemIdentifier,
                    to: itemIdentifier
                )
                remaining = remaining.subtracting(.nameFields)
            }
        }

        if remaining.intersects(with: .attrFields) {
            try await progress.withChild {
                try await setAttributes(
                    item,
                    fields: changedFields,
                    session: session
                )
                remaining = remaining.subtracting(.attrFields)
            }
        }

        if !remaining.isEmpty {
            logger.fault("Unhandled fields: \(remaining.desc)")
        }
        let item = try await progress.withChild {
            try await session.item(for: itemIdentifier)
        }
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

        return try await progress.withChild {
            let attrs = try await session.attributes(for: identifier)
            if case .directory = attrs.type {
                try await session.removeDirectory(for: identifier)
            } else {
                try await session.removeFile(for: identifier)
            }
        }
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

    private func read(
        _ itemIdentifier: NSFileProviderItemIdentifier,
        range: NSRange? = nil,
        progress: Progress,
        session: Session
    ) async throws -> (URL, NSFileProviderItem, NSRange) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path(), contents: nil)
        else {
            throw NSFileProviderError(.insufficientQuota)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let item = try await session.item(for: itemIdentifier)
        let range = range.clamped(to: Int(item.size))
        logger.debug(
            """
            Download \(itemIdentifier.desc) \
            with range(\(range.location), \(range.length)) \
            into \(url.path())
            """
        )

        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = Int64(range.length)
        let speedometer = Speedometer(progress: progress)

        try handle.seek(toOffset: UInt64(range.location))
        try await session.withFile(
            for: itemIdentifier,
            accessType: .readOnly
        ) { file in
            for try await data in file.stream(
                offset: UInt64(range.location),
                length: UInt64(range.length)
            ) {
                if progress.isCancelled {
                    throw CocoaError(.userCancelled)
                }
                try handle.write(contentsOf: data)
                if let progress = speedometer.update(delta: data.count) {
                    logger.debug(
                        "Downloading \(itemIdentifier.desc): \(progress)"
                    )
                }
            }
        }

        logger.debug(
            "Downloaded \(itemIdentifier.desc): \(speedometer.finalize())"
        )
        return (url, item, range)
    }

    private func write(
        _ itemIdentifier: NSFileProviderItemIdentifier,
        basedOn itemTemplate: NSFileProviderItem,
        contents url: URL?,
        fileSystemFlags: NSFileProviderFileSystemFlags = [],
        progress: Progress,
        session: Session,
    ) async throws {
        guard let url = url, let ds = itemTemplate.documentSize,
            let documentSize = ds
        else {
            logger.fault(
                "Missing contents URL or document size for \(itemTemplate.filename)"
            )
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let fp = try FileHandle(forReadingFrom: url)
        defer { try? fp.close() }

        logger.debug("Upload \(itemIdentifier.desc) from \(url.path())")

        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = Int64(truncating: documentSize)
        let speedometer = Speedometer(progress: progress)

        try await session.withFile(
            for: itemIdentifier,
            accessType: .writeOnly,
            mode: fileSystemFlags.permissions,
        ) { file in
            try await file.withAsyncWriter { writer in
                while let data = try fp.read(upToCount: 102400) {
                    if progress.isCancelled {
                        throw CocoaError(.userCancelled)
                    }
                    try await writer.write(data: data)
                    if let progress = speedometer.update(delta: data.count) {
                        logger.debug(
                            "Uploading \(itemIdentifier.desc): \(progress)"
                        )
                    }
                }
            }
        }

        logger.debug(
            "Uploaded \(itemIdentifier.desc): \(speedometer.finalize())"
        )
    }

    private func setAttributes(
        _ item: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        session: Session
    ) async throws {
        var changes: [String] = []

        let accessTime =
            fields.contains(.lastUsedDate)
            ? item.lastUsedDate ?? nil : nil
        if let accessTime = accessTime {
            changes.append("accessTime: \(accessTime)")
        }

        let modifyTime =
            fields.contains(.contentModificationDate)
            ? item.contentModificationDate ?? nil : nil
        if let modifyTime = modifyTime {
            changes.append("modifyTime: \(modifyTime)")
        }

        let permissions =
            fields.contains(.fileSystemFlags)
            ? item.fileSystemFlags?.permissions : nil
        if let permissions = permissions {
            changes.append(
                "permissions: \(String(permissions, radix: 8))"
            )
        }
        if let typeAndCreator = item.typeAndCreator {
            changes.append("typeAndCreator: \(typeAndCreator)")
        }
        logger.notice(
            "Set attributes of \(item.expectedId.desc): \(changes.joined(separator: ", "))"
        )
        try await session.setAttributes(
            for: item.expectedId,
            permissions: permissions,
            accessTime: accessTime,
            modifyTime: modifyTime,
        )
    }
}
