import Common
import FileProvider
import SwiftLibSSH
import UniformTypeIdentifiers

private let logger = Logger(category: "Extension")

public class Extension: NSObject, NSFileProviderReplicatedExtension,
    NSFileProviderPartialContentFetching
{
    static var agentClientFactory: () -> AgentClient = {
        AgentClient()
    }

    let manager: SessionManager
    let agent: AgentClient

    required public init(domain: NSFileProviderDomain) {
        agent = Self.agentClientFactory()

        do {
            let userInfo = try UserInfo.fromDictionary(domain.userInfo)
            let config = try ConnectionConfig(from: userInfo)
            manager = SessionManager(domain: domain, config: config)
            logger.debug("Init \(config)")
        } catch {
            manager = SessionManager(domain: domain, config: nil)
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
        let itemRef = await session.id(of: itemIdentifier)
        logger.debug("Item \(itemRef)")

        return try await progress.withChild {
            if itemIdentifier == .rootContainer || itemIdentifier == .workingSet
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
        let itemRef = await session.id(of: itemIdentifier)
        let url = FileManager.default.temporaryDirectory
            .appending(path: itemIdentifier.rawValue)
        guard FileManager.default.createFile(atPath: url.path(), contents: nil)
        else {
            throw NSFileProviderError(.insufficientQuota)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let item = try await session.item(for: itemIdentifier)
        logger.info("Download \(itemRef) into \(url.path())")

        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = Int64(item.size)
        let speedometer = Speedometer(progress: progress)

        try await session.withFile(
            for: itemIdentifier,
            accessType: .readOnly
        ) { file in
            for try await data in file.stream() {
                if progress.isCancelled {
                    throw CocoaError(.userCancelled)
                }
                try handle.write(contentsOf: data)
                if let progress = speedometer.update(delta: data.count) {
                    logger.debug("Downloading \(itemRef): \(progress)")
                }
            }
        }

        logger.info("Downloaded \(itemRef): \(speedometer.finalize())")
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
        let item = try await session.item(for: itemIdentifier)

        progress.kind = .file
        progress.fileOperationKind = .downloading
        let speedometer = Speedometer(progress: progress)

        let (url, fetchedRange) = try await session.stream(
            for: itemIdentifier,
            range: range,
            alignment: alignment,
            fileSize: item.size
        ) { data in
            if progress.isCancelled {
                throw CocoaError(.userCancelled)
            }
            if let update = speedometer.update(delta: data.count) {
                logger.debug("Streaming: \(update)")
            }
        }

        progress.totalUnitCount = Int64(fetchedRange.length)
        logger.info("Streamed: \(speedometer.finalize())")

        return (url, item, fetchedRange)
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
        logger.debug("Create \(item.desc) for \(fields.desc)")

        let itemIdentifier = try await session.child(
            of: item.parentItemIdentifier,
            path: item.filename
        )
        var remaining = fields.subtracting(.nameFields)
        let steps = progress.steps()

        if remaining.intersects(with: .writeFields) {
            guard let url = url else {
                logger.fault("Missing contents URL for \(item.desc)")
                throw CocoaError(.fileReadUnsupportedScheme)
            }

            let fileSize = try FileManager.default.size(of: url)
            let bufferSize = session.sftp.limits.writeLength()
            let fileTransferUnits = Int64(
                (fileSize + bufferSize - 1) / bufferSize
            )
            let fileSystemFlags =
                remaining.contains(.fileSystemFlags)
                ? item.fileSystemFlags ?? [] : []
            remaining.subtract([.fileSystemFlags, .contents])

            steps.add(weight: fileTransferUnits) { subprogress in
                try await self.write(
                    itemIdentifier,
                    contents: url,
                    fileSystemFlags: fileSystemFlags,
                    bufferSize: bufferSize,
                    progress: subprogress,
                    session: session
                )
            }
        } else if item.contentType == .folder {
            steps.add {
                try await session.createDirectory(for: itemIdentifier)
            }
        }

        if remaining.intersects(with: .attrFields) {
            remaining.subtract(.attrFields)
            steps.add {
                try await self.setAttributes(
                    item,
                    fields: fields,
                    session: session
                )
            }
        }

        if !remaining.isEmpty {
            logger.fault("Unhandled fields: \(remaining.desc)")
        }

        var createdItem: NSFileProviderItem?
        steps.add {
            createdItem = try await session.item(for: itemIdentifier)
        }

        try await steps.execute()
        return (createdItem!, [], false)
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
            logger.fault("Failed to modify item \(item.itemIdentifier)")
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
        logger.debug("Modify \(item.desc) for \(changedFields.desc)")

        var remaining = changedFields
        let steps = progress.steps()

        if remaining.intersects(with: .writeFields) {
            guard let newContents = newContents else {
                logger.fault("Missing URL for \(item.desc)")
                throw CocoaError(.fileReadUnsupportedScheme)
            }

            let fileSize = try FileManager.default.size(of: newContents)
            let bufferSize = session.sftp.limits.writeLength()
            let fileTransferUnits = Int64(
                (fileSize + bufferSize - 1) / bufferSize
            )
            let fileSystemFlags =
                remaining.contains(.fileSystemFlags)
                ? item.fileSystemFlags ?? [] : []
            remaining.subtract([.fileSystemFlags, .contents])

            steps.add(weight: fileTransferUnits) { subprogress in
                try await self.write(
                    item.itemIdentifier,
                    contents: newContents,
                    fileSystemFlags: fileSystemFlags,
                    bufferSize: bufferSize,
                    progress: subprogress,
                    session: session
                )
            }
        }

        if remaining.intersects(with: .nameFields) {
            remaining.subtract(.nameFields)
            steps.add {
                try await session.move(
                    item.itemIdentifier,
                    toParent: item.parentId,
                    name: item.filename,
                    ifParentNotExists:
                        item.parentId == .trashContainer ? .create : .fail
                )
            }
        }

        if remaining.intersects(with: .attrFields) {
            remaining.subtract(.attrFields)
            steps.add {
                try await self.setAttributes(
                    item,
                    fields: changedFields,
                    session: session
                )
            }
        }

        if !remaining.isEmpty {
            logger.fault("Unhandled fields: \(remaining.desc)")
        }

        var modifiedItem: NSFileProviderItem?
        steps.add {
            modifiedItem = try await session.item(for: item.itemIdentifier)
        }

        try await steps.execute()
        return (modifiedItem, [], false)
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
            logger.fault("Failed to delete item \(identifier)")
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
        let itemRef = await session.id(of: identifier)
        logger.debug("Delete \(itemRef)")

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
        logger.debug("Create enumerator for \(containerItemIdentifier.desc)")
        return Enumerator(
            manager: manager,
            itemIdentifier: containerItemIdentifier
        )
    }

    private func write(
        _ itemIdentifier: NSFileProviderItemIdentifier,
        contents url: URL,
        fileSystemFlags: NSFileProviderFileSystemFlags = [],
        bufferSize: UInt64,
        progress: Progress,
        session: Session,
    ) async throws {
        let itemRef = await session.id(of: itemIdentifier)
        let fp = try FileHandle(forReadingFrom: url)
        defer { try? fp.close() }

        logger.info("Upload \(itemRef) from \(url.path())")
        let size = try FileManager.default.size(of: url)

        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.totalUnitCount = Int64(size)
        let speedometer = Speedometer(progress: progress)

        try await session.withFile(
            for: itemIdentifier,
            accessType: .writeOnly,
            mode: fileSystemFlags.permissions,
        ) { file in
            try await file.withAsyncWriter { writer in
                while let data = try fp.read(upToCount: Int(bufferSize)) {
                    if progress.isCancelled {
                        throw CocoaError(.userCancelled)
                    }
                    try await writer.write(data: data)
                    if let progress = speedometer.update(delta: data.count) {
                        logger.debug("Uploading \(itemRef): \(progress)")
                    }
                }
            }
        }

        logger.info("Uploaded \(itemRef): \(speedometer.finalize())")
    }

    private func setAttributes(
        _ item: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        session: Session
    ) async throws {
        try await session.setAttributes(
            for: session.child(of: item.parentId, path: item.filename),
            permissions: fields.contains(.fileSystemFlags)
                ? item.fileSystemFlags?.permissions : nil,
            accessTime: fields.contains(.lastUsedDate)
                ? item.lastUsedDate ?? nil : nil,
            modifyTime: fields.contains(.contentModificationDate)
                ? item.contentModificationDate ?? nil : nil,
        )
    }
}
