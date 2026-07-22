import Common
import FileProvider
import Synchronization
import UniformTypeIdentifiers

private let logger = Logger(category: "Extension")

public class Extension: NSObject, NSFileProviderReplicatedExtension,
    NSFileProviderPartialContentFetching, NSFileProviderServicing
{
    private let client: CoreClient

    required public init(domain: NSFileProviderDomain) {
        client = CoreClient(domain: domain)
        logger.debug("Init \(domain)")
        super.init()
    }

    public init(client: CoreClient) {
        self.client = client
        super.init()
    }

    public func invalidate() {}

    func item(
        for identifier: NSFileProviderItemIdentifier,
    ) async throws -> FPItem {
        try await FPItem(item: client.item(for: identifier))
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
        let (url, item) = try await client.download(
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

        let (url, fetchedRange) = try await client.stream(
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

        let parentId = item.parentItemIdentifier
        let filename = item.filename
        var remaining = fields.subtracting(.nameFields)
        let steps = progress.steps()
        var createdItem: Item?

        if item.contentType == .symbolicLink,
            remaining.intersects(with: .writeFields),
            let target = item.symlinkTargetPath ?? nil
        {
            remaining.subtract([.contents])

            steps.add {
                createdItem = try await self.client.createSymlink(
                    parentId: parentId,
                    name: filename,
                    target: target
                )
            }
        }

        if item.contentType == .folder {
            steps.add {
                createdItem = try await self.client.createDirectory(
                    parentId: parentId,
                    name: filename
                )
            }
        }

        if let url = url, remaining.intersects(with: .writeFields) {
            let fileSize = try FileManager.default.size(of: url)
            let limits = try await client.limits()
            let chunkSize = limits.maxWriteLength
            let fileTransferUnits = Int64(
                (fileSize + chunkSize - 1) / chunkSize
            )
            let fileSystemFlags =
                remaining.contains(.fileSystemFlags)
                ? item.fileSystemFlags ?? [] : []
            remaining.subtract([.fileSystemFlags, .contents])

            steps.add(weight: fileTransferUnits) { subprogress in
                createdItem = try await self.client.upload(
                    parentId: parentId,
                    name: filename,
                    file: url,
                    flags: .init(from: fileSystemFlags),
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

        try await steps.execute()
        return (FPItem(item: createdItem!), [], false)
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
            let limits = try await client.limits()
            let chunkSize = limits.maxWriteLength
            let fileTransferUnits = Int64(
                (fileSize + chunkSize - 1) / chunkSize
            )
            let fileSystemFlags =
                remaining.contains(.fileSystemFlags)
                ? item.fileSystemFlags ?? [] : []
            remaining.subtract([.fileSystemFlags, .contents])

            steps.add(weight: fileTransferUnits) { subprogress in
                // Upload to the file's current parent/name; rename/move
                // happens in a later step if .nameFields is present.
                let currentParent = try await self.client.parent(
                    of: item.itemIdentifier
                )
                let currentName = try await self.client.name(
                    of: item.itemIdentifier
                )
                _ = try await self.client.upload(
                    parentId: currentParent,
                    name: currentName,
                    file: newContents,
                    flags: .init(from: fileSystemFlags),
                    progress: subprogress
                )
            }
        }

        if remaining.intersects(with: .nameFields) {
            remaining.subtract(.nameFields)
            steps.add {
                try await self.client.move(
                    item.itemIdentifier,
                    toParent: item.parentId,
                    name: item.filename
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
            let item = try await client.item(for: identifier)
            if item.kind == .folder {
                try await client.removeDirectory(for: identifier)
            } else {
                try await client.removeFile(for: identifier)
            }
        }
    }

    public func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        logger.debug("Create enumerator for \(containerItemIdentifier.desc)")
        return Enumerator(
            client: client,
            itemIdentifier: containerItemIdentifier
        )
    }

    private func setAttributes(
        _ item: NSFileProviderItem,
        fields: NSFileProviderItemFields
    ) async throws {
        try await client.setAttributes(
            for: client.child(of: item.parentId, name: item.filename),
            flags: fields.contains(.fileSystemFlags)
                ? .from(item.fileSystemFlags) : nil,
            accessTime: fields.contains(.lastUsedDate)
                ? item.lastUsedDate ?? nil : nil,
            modifyTime: fields.contains(.contentModificationDate)
                ? item.contentModificationDate ?? nil : nil,
        )
    }

    public func supportedServiceSources(
        for itemIdentifier: NSFileProviderItemIdentifier,
        completionHandler:
            @escaping ([any NSFileProviderServiceSource]?, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        completionHandler([client], nil)
        progress.completedUnitCount = 1
        return progress
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
            let coreError = CoreError(from: error)
            trace.log(logger, error: coreError)
            onError(coreError.asNSError)
        }
    }
    return progress
}
