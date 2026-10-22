import FileProvider
import Foundation
import Synchronization

private let logger = Logger(category: "CoreClient")

public final class CoreClient: NSObject, NSFileProviderServiceSource,
    NSXPCListenerDelegate
{
    private enum State {
        case idle
        case waiting
        case connected(NSXPCConnection)
        case detaching(NSXPCConnection)
        case detached
        case suspended
    }

    public let serviceName = SSHadow.extensionServiceName
    private let domain: NSFileProviderDomain
    private let listener = NSXPCListener.anonymous()
    private let groupUrl: URL
    private let state = Mutex(State.idle)

    private static let clients = Mutex<
        [NSFileProviderDomainIdentifier: CoreClient]
    >([:])

    // File Provider can create several extensions for a domain in one process.
    public static func shared(for domain: NSFileProviderDomain) -> CoreClient {
        clients.withLock { clients in
            if let client = clients[domain.identifier] {
                return client
            }
            let client = CoreClient(domain: domain)
            clients[domain.identifier] = client
            return client
        }
    }

    public init(
        domain: NSFileProviderDomain,
        groupUrl: URL = SSHadow.groupUrl
    ) {
        self.domain = domain
        self.groupUrl = groupUrl

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

    private var connection: NSXPCConnection? {
        state.withLock {
            switch $0 {
            case .connected(let connection), .detaching(let connection):
                connection
            case .idle, .waiting, .detached, .suspended:
                nil
            }
        }
    }

    private func suspend() async {
        let shouldSuspend = state.withLock {
            guard case .waiting = $0 else { return false }
            $0 = .suspended
            return true
        }
        guard shouldSuspend else { return }
        await domain.suspend(
            reason: "SSHadow needs to be running in order to sync this volume.",
            options: .temporary
        )
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ExtXPC.self)
        connection.exportedObject = ExtHandler(
            client: self,
            connection: connection
        )
        connection.remoteObjectInterface = NSXPCInterface(with: CoreXPC.self)
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.disconnected(connection)
        }
        connection.interruptionHandler = { connection.invalidate() }
        state.withLock { $0 = .connected(connection) }
        connection.resume()

        logger.info("Core XPC connected")
        return true
    }

    private func disconnected(_ connection: NSXPCConnection) {
        let current = state.withLock {
            switch $0 {
            case .connected(let current) where current === connection:
                $0 = .waiting
            case .detaching(let current) where current === connection:
                $0 = .detached
            default:
                return false
            }
            return true
        }
        guard current else {
            logger.info("Ignored stale Core XPC disconnect")
            return
        }
        Task { await suspend() }
        logger.info("Core XPC disconnected")
    }

    fileprivate func detach(_ connection: NSXPCConnection) {
        state.withLock {
            if case .connected(let current) = $0, current === connection {
                $0 = .detaching(current)
            }
        }
    }

    private func requireConnection() async throws(CoreError) -> NSXPCConnection
    {
        if connection == nil {
            logger.info("Waiting for Core XPC to connect")
            let deadline = ContinuousClock.now + .seconds(1)
            while connection == nil, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let connection else {
            await suspend()
            logger.error("Core XPC never connected")
            throw CoreError.serviceUnreachable
        }
        return connection
    }

    private func perform<Response: Message>(
        _ handle: (NSXPCConnection) async throws -> Data
    ) async throws(CoreError) -> Response {
        let connection = try await requireConnection()
        let result: CoreResult<Response>
        do {
            result = try CoreResult.decoded(from: try await handle(connection))
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

    public func ignoreFilenames() async throws(CoreError) -> [String] {
        let response = try await perform(IgnoreFilenamesRequest())
        return response.filenames
    }

    public func isExcluded(
        _ name: String,
        in parentId: NSFileProviderItemIdentifier,
        isDirectory: Bool,
        ignoreFiles: IgnoreFiles
    ) async throws(CoreError) -> Bool {
        let response = try await perform(
            ExcludedRequest(
                parentId: parentId.rawValue,
                name: name,
                isDirectory: isDirectory,
                ignoreFiles: ignoreFiles
            )
        )
        return response.excluded
    }

    public func upload(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        file: URL,
        chunkSize: UInt64 = Limits.defaultBufferSize,
        progress: Progress
    ) async throws(CoreError) -> Item {
        let stagedUrl = groupUrl.appending(path: UUID().uuidString)
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

private final class ExtHandler: NSObject, ExtXPC {
    private weak var client: CoreClient?
    private weak var connection: NSXPCConnection?

    init(client: CoreClient, connection: NSXPCConnection) {
        self.client = client
        self.connection = connection
    }

    func attach(reply: @escaping @Sendable () -> Void) {
        reply()
    }

    func detach(reply: @escaping @Sendable () -> Void) {
        if let client, let connection {
            client.detach(connection)
        }
        reply()
    }
}
