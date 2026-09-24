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

    private func suspend() async {
        guard attached else { return }
        await domain.suspend(
            reason: "SSHadow needs to be running in order to sync this volume.",
            options: .temporary
        )
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
            Task { await self.suspend() }
            logger.info("Core XPC disconnected")
        }
        connection.interruptionHandler = { connection.invalidate() }
        connection.resume()
        self.connection = connection

        logger.info("Core XPC connected")
        return true
    }

    public func attach() async {}

    public func detach() async {
        attached = false
    }

    private func requireService() async throws(CoreError) -> CoreXPC {
        if connection == nil {
            logger.info("Waiting for Core XPC to connect")
            let deadline = ContinuousClock.now + .seconds(1)
            while connection == nil, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let service = connection?.remoteObjectProxy as? CoreXPC else {
            await suspend()
            logger.error("Core XPC never connected")
            throw CoreError.serviceUnreachable
        }
        return service
    }

    private func perform<Response: Message>(
        _ handle: (CoreXPC) async throws -> Data
    ) async throws(CoreError) -> Response {
        let service = try await requireService()
        let result: CoreResult<Response>
        do {
            result = try CoreResult.decoded(from: try await handle(service))
        } catch {
            logger.error("Request failed: \(error)")
            throw CoreError(from: error)
        }
        return try result.get()
    }

    private func perform<Request: CoreRequestType>(
        _ request: Request
    ) async throws(CoreError) -> Request.Response {
        return try await perform {
            try await $0.handle(request.wrapped.encoded())
        }
    }

    private func perform<Request: CoreProgressRequestType>(
        _ request: Request,
        progressEndpoint: NSXPCListenerEndpoint
    ) async throws(CoreError) -> Request.Response {
        return try await perform {
            try await $0.handle(
                request.wrapped.encoded(),
                progressEndpoint: progressEndpoint
            )
        }
    }

    public func name(
        of itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) -> String {
        let response = try await perform(
            NameRequest(itemId: itemId.rawValue)
        )
        return response.name
    }

    public func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        name: String
    ) async throws(CoreError) -> NSFileProviderItemIdentifier {
        let response = try await perform(
            ChildRequest(parentId: parentId.rawValue, name: name)
        )
        return NSFileProviderItemIdentifier(response.itemId)
    }

    public func parent(
        of itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) -> NSFileProviderItemIdentifier {
        let response = try await perform(
            ParentRequest(itemId: itemId.rawValue)
        )
        return NSFileProviderItemIdentifier(response.itemId)
    }

    public func item(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) -> Item {
        let response = try await perform(
            ItemRequest(itemId: itemId.rawValue)
        )
        return response.item
    }

    public func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) -> [Item] {
        let response = try await perform(
            ListRequest(itemId: itemId.rawValue)
        )
        return response.fileInfos
    }

    public func watch(
        itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) {
        _ = try await perform(WatchRequest(itemId: itemId.rawValue))
    }

    public func unwatch(
        itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) {
        _ = try await perform(UnwatchRequest(itemId: itemId.rawValue))
    }

    public func currentAnchor() async throws(CoreError) -> UInt64 {
        let response = try await perform(CurrentAnchorRequest())
        return response.anchor
    }

    public func changes(
        since anchor: UInt64
    ) async throws(CoreError) -> (UInt64, [Change]) {
        let response = try await perform(ChangesRequest(anchor: anchor))
        return (response.anchor, response.changes)
    }

    @discardableResult
    public func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        flags: Item.Flags? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws(CoreError) -> Item {
        let response = try await perform(
            SetAttributesRequest(
                itemId: itemId.rawValue,
                flags: flags,
                accessTime: accessTime,
                modifyTime: modifyTime
            )
        )
        return response.item
    }

    public func createSymlink(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        target: String
    ) async throws(CoreError) -> Item {
        let response = try await perform(
            CreateSymlinkRequest(
                parentId: parentId.rawValue,
                name: name,
                target: target
            )
        )
        return response.item
    }

    public func createDirectory(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        flags: Item.Flags,
        ifExists: OnExists = .fail
    ) async throws(CoreError) -> Item {
        let response = try await perform(
            CreateDirectoryRequest(
                parentId: parentId.rawValue,
                name: name,
                flags: flags,
                ifExists: ifExists
            )
        )
        return response.item
    }

    @discardableResult
    public func move(
        _ itemId: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String
    ) async throws(CoreError) -> Item {
        let response = try await perform(
            MoveRequest(
                itemId: itemId.rawValue,
                newParentId: newParentId.rawValue,
                newName: newName
            )
        )
        return response.item
    }

    public func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) {
        _ = try await perform(RemoveFileRequest(itemId: itemId.rawValue))
    }

    public func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(CoreError) {
        _ = try await perform(RemoveDirectoryRequest(itemId: itemId.rawValue))
    }

    public func limits() async throws(CoreError) -> Limits {
        let response = try await perform(LimitsRequest())
        return response.limits
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
        let response = try await perform(
            UploadRequest(
                parentId: parentId.rawValue,
                name: name,
                file: stagedUrl,
                flags: flags,
                chunkSize: chunkSize
            ),
            progressEndpoint: sync.endpoint
        )
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
        let response = try await perform(
            DownloadRequest(itemId: itemId.rawValue, chunkSize: chunkSize),
            progressEndpoint: sync.endpoint
        )
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
        let response = try await perform(
            StreamRequest(itemId: itemId.rawValue, range: range),
            progressEndpoint: sync.endpoint
        )
        return (response.url, response.range)
    }
}
