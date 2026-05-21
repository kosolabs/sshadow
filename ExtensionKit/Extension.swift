import Common
import FileProvider
import Synchronization
import UniformTypeIdentifiers

private let logger = Logger(category: "Extension")

private func disconnect(domain: NSFileProviderDomain) {
    Task {
        do {
            try await domain.disconnect()
        } catch {
            logger.error("Failed to disconnect \(domain): \(error)")
        }
    }
}

public class Extension: NSObject, NSFileProviderReplicatedExtension,
    NSFileProviderPartialContentFetching
{
    private let agent: AgentClient
    private let invalidated: Flag = Flag(false)

    required public init(domain: NSFileProviderDomain) {
        let domainId = UUID(uuidString: domain.identifier.rawValue)!
        let invalidated = self.invalidated
        agent = AgentClient(
            domainId: domainId,
            cancellationHandler: { _ in
                if !invalidated.isSet {
                    disconnect(domain: domain)
                }
            }
        )
        logger.debug("Init \(domain)")
        super.init()
    }

    public init(agent: AgentClient) {
        self.agent = agent
        super.init()
    }

    public func invalidate() {
        invalidated.set()
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
    ) async throws -> FPItem {
        try await FPItem(item: agent.item(for: identifier))
    }

    public func item(
        for itemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        withProgress { progress in
            try await self.item(
                for: itemIdentifier,
                request: request,
                progress: progress
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
        progress: Progress
    ) async throws -> NSFileProviderItem {
        logger.debug("Item \(itemIdentifier.desc)")

        return try await progress.withChild {
            if itemIdentifier == .rootContainer || itemIdentifier == .workingSet
            {
                return SpecialItem(itemIdentifier: itemIdentifier)
            }

            return try await item(for: itemIdentifier)
        }
    }

    public func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        withProgress { progress in
            try await self.fetchContents(
                for: itemIdentifier,
                version: requestedVersion,
                request: request,
                progress: progress
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
        progress: Progress
    ) async throws -> (URL, NSFileProviderItem) {
        let (url, item) = try await agent.download(
            itemId: itemIdentifier,
            progress: progress
        )
        return (url, FPItem(item: item))
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
        withProgress { progress in
            try await self.fetchPartialContents(
                for: itemIdentifier,
                version: requestedVersion,
                request: request,
                minimalRange: range,
                aligningTo: alignment,
                options: options,
                progress: progress
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
        minimalRange requestedRange: NSRange,
        aligningTo alignment: Int,
        options: NSFileProviderFetchContentsOptions = [],
        progress: Progress
    ) async throws -> (URL, NSFileProviderItem, NSRange) {
        let item = try await item(for: itemIdentifier)

        progress.kind = .file
        progress.fileOperationKind = .downloading

        let (url, fetchedRange) = try await agent.stream(
            itemId: itemIdentifier,
            range: requestedRange.asRange(),
            progress: progress
        )

        return (url, item, fetchedRange.asNSRange())
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
        withProgress { progress in
            try await self.createItem(
                basedOn: itemTemplate,
                fields: fields,
                contents: url,
                options: options,
                request: request,
                progress: progress
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
        progress: Progress
    ) async throws -> (NSFileProviderItem, NSFileProviderItemFields, Bool) {
        logger.debug("Create \(item.desc) for \(fields.desc)")

        let itemIdentifier = try await agent.child(
            of: item.parentItemIdentifier,
            path: item.filename
        )
        var remaining = fields.subtracting(.nameFields)
        let steps = progress.steps()

        if item.contentType == .symbolicLink,
            remaining.intersects(with: .writeFields),
            let target = item.symlinkTargetPath ?? nil
        {
            remaining.subtract([.contents])

            steps.add {
                try await self.agent.createSymlink(
                    at: itemIdentifier,
                    to: target
                )
            }
        }

        if item.contentType == .folder {
            steps.add {
                try await self.agent.createDirectory(for: itemIdentifier)
            }
        }

        if let url = url, remaining.intersects(with: .writeFields) {
            let fileSize = try FileManager.default.size(of: url)
            let limits = try await agent.limits()
            let chunkSize = limits.maxWriteLength
            let fileTransferUnits = Int64(
                (fileSize + chunkSize - 1) / chunkSize
            )
            let fileSystemFlags =
                remaining.contains(.fileSystemFlags)
                ? item.fileSystemFlags ?? [] : []
            remaining.subtract([.fileSystemFlags, .contents])

            steps.add(weight: fileTransferUnits) { subprogress in
                try await self.agent.upload(
                    itemId: itemIdentifier,
                    file: url,
                    mode: fileSystemFlags.permissions,
                    progress: subprogress
                )
            }
        }

        if remaining.intersects(with: .attrFields) {
            remaining.subtract(.attrFields)
            steps.add {
                try await self.setAttributes(item, fields: fields)
            }
        }

        if !remaining.isEmpty {
            logger.fault("Unhandled fields: \(remaining.desc)")
        }

        var createdItem: NSFileProviderItem?
        steps.add {
            createdItem = try await self.item(for: itemIdentifier)
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
        withProgress { progress in
            try await self.modifyItem(
                item,
                baseVersion: version,
                changedFields: changedFields,
                contents: newContents,
                options: options,
                request: request,
                progress: progress
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
        progress: Progress
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
            let limits = try await agent.limits()
            let chunkSize = limits.maxWriteLength
            let fileTransferUnits = Int64(
                (fileSize + chunkSize - 1) / chunkSize
            )
            let fileSystemFlags =
                remaining.contains(.fileSystemFlags)
                ? item.fileSystemFlags ?? [] : []
            remaining.subtract([.fileSystemFlags, .contents])

            steps.add(weight: fileTransferUnits) { subprogress in
                try await self.agent.upload(
                    itemId: item.itemIdentifier,
                    file: newContents,
                    mode: fileSystemFlags.permissions,
                    progress: subprogress
                )
            }
        }

        if remaining.intersects(with: .nameFields) {
            remaining.subtract(.nameFields)
            steps.add {
                try await self.agent.move(
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
                try await self.setAttributes(item, fields: changedFields)
            }
        }

        if !remaining.isEmpty {
            logger.fault("Unhandled fields: \(remaining.desc)")
        }

        var modifiedItem: NSFileProviderItem?
        steps.add {
            modifiedItem = try await self.item(for: item.itemIdentifier)
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
        withProgress { progress in
            try await self.deleteItem(
                identifier: identifier,
                baseVersion: version,
                options: options,
                request: request,
                progress: progress
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
        progress: Progress
    ) async throws {
        logger.debug("Delete \(identifier.desc)")
        return try await progress.withChild {
            let item = try await agent.item(for: identifier)
            if item.kind == .folder {
                try await agent.removeDirectory(for: identifier)
            } else {
                try await agent.removeFile(for: identifier)
            }
        }
    }

    public func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        logger.debug("Create enumerator for \(containerItemIdentifier.desc)")
        return Enumerator(
            agent: agent,
            itemIdentifier: containerItemIdentifier
        )
    }

    private func setAttributes(
        _ item: NSFileProviderItem,
        fields: NSFileProviderItemFields
    ) async throws {
        try await agent.setAttributes(
            for: agent.child(of: item.parentId, path: item.filename),
            permissions: fields.contains(.fileSystemFlags)
                ? item.fileSystemFlags?.permissions : nil,
            accessTime: fields.contains(.lastUsedDate)
                ? item.lastUsedDate ?? nil : nil,
            modifyTime: fields.contains(.contentModificationDate)
                ? item.contentModificationDate ?? nil : nil,
        )
    }
}

private func withProgress<T>(
    progress: Progress = Progress(),
    _ perform: @escaping (Progress) async throws -> T,
    onSuccess: @escaping (T) -> Void,
    onError: @escaping (Error) -> Void,
    file: String = #fileID,
    line: Int = #line,
) -> Progress {
    let trace = StackTrace.capture(file: file, line: line)

    Task {
        do {
            let result = try await perform(progress)
            onSuccess(result)
        } catch {
            trace.log(logger, error: error)
            onError(error)
        }
    }
    return progress
}
