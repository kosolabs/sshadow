import FileProvider
import Foundation

private let logger = Logger(category: "CoreClient")

public final class CoreClient: NSObject, NSFileProviderServiceSource,
    NSXPCListenerDelegate, ExtXPC
{
    public let serviceName = SSHadow.extensionServiceName
    private let domain: NSFileProviderDomain
    private let listener = NSXPCListener.anonymous()
    private var connection: NSXPCConnection?
    private let sharedUrl: URL
    private var attached: Bool = true

    public init(
        domain: NSFileProviderDomain,
        sharedUrl: URL = SSHadow.groupUrl
    ) {
        self.domain = domain
        self.sharedUrl = sharedUrl

        super.init()
        listener.delegate = self
        listener.resume()
    }

    deinit {
        connection?.invalidate()
    }

    public func makeListenerEndpoint() throws -> NSXPCListenerEndpoint {
        listener.endpoint
    }

    private func suspend() {
        guard attached else { return }
        Task {
            do {
                try await domain.suspend(
                    reason:
                        "SSHadow needs to be running in order to sync this volume.",
                    options: .temporary
                )
            } catch {
                logger.error("Failed to suspend \(domain): \(error)")
            }
        }
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        attached = true
        connection.exportedInterface = NSXPCInterface(with: ExtXPC.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: CoreXPC.self)
        connection.invalidationHandler = {
            self.connection = nil
            self.suspend()
            logger.debug("Core XPC disconnected")
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()
        self.connection = connection

        logger.debug("Core XPC connected")
        return true
    }

    public func attach() async {}

    public func detach() async {
        attached = false
    }

    private func perform(
        _ handle: (CoreXPC) async throws -> Data
    ) async throws(CoreError) -> CoreResponse {
        guard let service = connection?.remoteObjectProxy as? CoreXPC else {
            throw CoreError.serviceUnreachable
        }
        do {
            let response = try await handle(service)
            let result = try CoreResult.decoded(from: response)
            logger.debug("Result: \(result)")
            return try result.get()
        } catch let error as CoreError {
            throw error
        } catch {
            logger.error("Request failed: \(error)")
            throw CoreError(from: error)
        }
    }

    private func perform(
        _ request: CoreRequest
    ) async throws(CoreError) -> CoreResponse {
        logger.debug("Request: \(request)")
        return try await perform { try await $0.handle(request.encoded()) }
    }

    private func perform(
        _ request: CoreProgressRequest,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws(CoreError) -> CoreResponse {
        logger.debug("Request: \(request)")
        return try await perform {
            try await $0.handle(
                request.encoded(),
                progressEndpoint: progressEndpoint
            )
        }
    }

    public func name(
        of itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) -> String {
        let reply = try await perform(
            .name(NameRequest(domainId: domain.id, itemId: itemId.rawValue))
        )
        guard case .name(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return response.name
    }

    public func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        name: String
    ) async throws(CoreError) -> NSFileProviderItemIdentifier {
        let reply = try await perform(
            .child(
                ChildRequest(
                    domainId: domain.id,
                    parentId: parentId.rawValue,
                    name: name
                )
            )
        )
        guard case .child(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return NSFileProviderItemIdentifier(response.itemId)
    }

    public func parent(
        of itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) -> NSFileProviderItemIdentifier {
        let reply = try await perform(
            .parent(
                ParentRequest(
                    domainId: domain.id,
                    itemId: itemId.rawValue
                )
            )
        )
        guard case .parent(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return NSFileProviderItemIdentifier(response.itemId)
    }

    public func item(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) -> Item {
        let reply = try await perform(
            .item(
                ItemRequest(domainId: domain.id, itemId: itemId.rawValue)
            )
        )
        guard case .item(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return response.item
    }

    public func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) -> [Item] {
        let reply = try await perform(
            .list(
                ListRequest(domainId: domain.id, itemId: itemId.rawValue)
            )
        )
        guard case .list(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return response.fileInfos
    }

    public func currentAnchor() async throws(CoreError) -> UInt64 {
        let reply = try await perform(
            .currentAnchor(CurrentAnchorRequest(domainId: domain.id))
        )
        guard case .currentAnchor(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return response.anchor
    }

    public func changes(
        since anchor: UInt64
    ) async throws(CoreError) -> (UInt64, [Change]) {
        let reply = try await perform(
            .changes(ChangesRequest(domainId: domain.id, anchor: anchor))
        )
        guard case .changes(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return (response.anchor, response.changes)
    }

    public func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        flags: Item.Flags? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws(CoreError) {
        let reply = try await perform(
            .setAttributes(
                SetAttributesRequest(
                    domainId: domain.id,
                    itemId: itemId.rawValue,
                    flags: flags,
                    accessTime: accessTime,
                    modifyTime: modifyTime
                )
            )
        )
        guard case .setAttributes = reply else {
            throw CoreError.unexpectedResponse
        }
    }

    public func createSymlink(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        target: String
    ) async throws(CoreError) -> Item {
        let reply = try await perform(
            .createSymlink(
                CreateSymlinkRequest(
                    domainId: domain.id,
                    parentId: parentId.rawValue,
                    name: name,
                    target: target
                )
            )
        )
        guard case .createSymlink(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return response.item
    }

    public func createDirectory(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        mode: mode_t = 0o700,
        ifExists: OnExists = .fail
    ) async throws(CoreError) -> Item {
        let reply = try await perform(
            .createDirectory(
                CreateDirectoryRequest(
                    domainId: domain.id,
                    parentId: parentId.rawValue,
                    name: name,
                    mode: mode,
                    ifExists: ifExists
                )
            )
        )
        guard case .createDirectory(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return response.item
    }

    public func move(
        _ itemId: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String
    ) async throws(CoreError) {
        let reply = try await perform(
            .move(
                MoveRequest(
                    domainId: domain.id,
                    itemId: itemId.rawValue,
                    newParentId: newParentId.rawValue,
                    newName: newName
                )
            )
        )
        guard case .move = reply else {
            throw CoreError.unexpectedResponse
        }
    }

    public func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) {
        let reply = try await perform(
            .removeFile(
                RemoveFileRequest(domainId: domain.id, itemId: itemId.rawValue)
            )
        )
        guard case .removeFile = reply else {
            throw CoreError.unexpectedResponse
        }
    }

    public func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) {
        let reply = try await perform(
            .removeDirectory(
                RemoveDirectoryRequest(
                    domainId: domain.id,
                    itemId: itemId.rawValue
                )
            )
        )
        guard case .removeDirectory = reply else {
            throw CoreError.unexpectedResponse
        }
    }

    public func limits() async throws(CoreError) -> Limits {
        let reply = try await perform(
            .limits(
                LimitsRequest(
                    domainId: domain.id
                )
            )
        )
        guard case .limits(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return Limits(
            maxReadLength: response.maxReadLength,
            maxWriteLength: response.maxWriteLength
        )
    }

    public func upload(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        file: URL,
        flags: Item.Flags,
        chunkSize: UInt64 = Limits.defaultBufferSize,
        progress: Progress
    ) async throws(CoreError) -> Item {
        let stagedUrl = sharedUrl.appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: file, to: stagedUrl)
        } catch {
            throw CoreError(from: error)
        }
        defer { try? FileManager.default.moveItem(at: stagedUrl, to: file) }

        progress.kind = .file
        progress.fileOperationKind = .uploading

        let sync = XPCProgressSubscriber(progress: progress)
        let reply = try await perform(
            .upload(
                UploadRequest(
                    domainId: domain.id,
                    parentId: parentId.rawValue,
                    name: name,
                    file: stagedUrl,
                    flags: flags,
                    chunkSize: chunkSize
                )
            ),
            progressEndpoint: sync.endpoint
        )
        guard case .upload(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return response.item
    }

    public func download(
        itemId: NSFileProviderItemIdentifier,
        chunkSize: UInt64 = Limits.defaultBufferSize,
        progress: Progress
    ) async throws(CoreError) -> (URL, Item) {
        progress.kind = .file
        progress.fileOperationKind = .downloading

        let sync = XPCProgressSubscriber(progress: progress)
        let reply = try await perform(
            .download(
                DownloadRequest(
                    domainId: domain.id,
                    itemId: itemId.rawValue,
                    chunkSize: chunkSize
                )
            ),
            progressEndpoint: sync.endpoint
        )
        guard case .download(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return (response.url, response.item)
    }

    public func stream(
        itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>,
        progress: Progress
    ) async throws(CoreError) -> (URL, Range<UInt64>) {
        progress.kind = .file
        progress.fileOperationKind = .downloading

        let sync = XPCProgressSubscriber(progress: progress)
        let reply = try await perform(
            .stream(
                StreamRequest(
                    domainId: domain.id,
                    itemId: itemId.rawValue,
                    range: range
                )
            ),
            progressEndpoint: sync.endpoint
        )
        guard case .stream(let response) = reply else {
            throw CoreError.unexpectedResponse
        }
        return (response.url, response.range)
    }
}
