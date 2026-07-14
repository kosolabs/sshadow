import FileProvider
import Foundation
import XPC

private let logger = Logger(category: "AgentClient")

public class AgentClient {
    private let domainId: UUID
    private let session: XPCSession
    private let sharedUrl: URL

    public convenience init(
        domainId: UUID,
        cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil
    ) {
        let session = try! XPCSession(
            machService: SSHadow.appServiceName,
            cancellationHandler: cancellationHandler
        )
        self.init(domainId: domainId, session: session)
    }

    public init(
        domainId: UUID,
        session: XPCSession,
        sharedUrl: URL = SSHadow.groupUrl
    ) {
        self.domainId = domainId
        self.session = session
        self.sharedUrl = sharedUrl
    }

    deinit {
        session.cancel(reason: "AgentClient deallocated")
    }

    private func perform(
        _ request: AgentRequest
    ) async throws(AgentError) -> AgentResponse {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                do {
                    try session.send(request) {
                        (result: Result<AgentResult, any Error>) in
                        continuation.resume(
                            with: Result { try result.get().get() }
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } catch let error as AgentError {
            throw error
        } catch let error as XPCRichError {
            logger.error("XPC failure: \(error)")
            throw AgentError.agentUnreachable
        } catch {
            logger.error("Request failed: \(error)")
            throw AgentError(from: error)
        }
    }

    public func name(
        of itemId: NSFileProviderItemIdentifier
    ) async throws(AgentError) -> String {
        let reply = try await perform(
            .name(NameRequest(domainId: domainId, itemId: itemId.rawValue))
        )
        guard case .name(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return response.name
    }

    public func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        name: String
    ) async throws(AgentError) -> NSFileProviderItemIdentifier {
        let reply = try await perform(
            .child(
                ChildRequest(
                    domainId: domainId,
                    parentId: parentId.rawValue,
                    name: name
                )
            )
        )
        guard case .child(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return NSFileProviderItemIdentifier(response.itemId)
    }

    public func parent(
        of itemId: NSFileProviderItemIdentifier
    ) async throws(AgentError) -> NSFileProviderItemIdentifier {
        let reply = try await perform(
            .parent(
                ParentRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue
                )
            )
        )
        guard case .parent(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return NSFileProviderItemIdentifier(response.itemId)
    }

    public func item(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(AgentError) -> Item {
        let reply = try await perform(
            .item(
                ItemRequest(domainId: domainId, itemId: itemId.rawValue)
            )
        )
        guard case .item(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return response.item
    }

    public func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(AgentError) -> [Item] {
        let reply = try await perform(
            .list(
                ListRequest(domainId: domainId, itemId: itemId.rawValue)
            )
        )
        guard case .list(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return response.fileInfos
    }

    public func currentAnchor() async throws(AgentError) -> UInt64 {
        let reply = try await perform(
            .currentAnchor(CurrentAnchorRequest(domainId: domainId))
        )
        guard case .currentAnchor(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return response.anchor
    }

    public func changes(
        since anchor: UInt64
    ) async throws(AgentError) -> (UInt64, [Change]) {
        let reply = try await perform(
            .changes(ChangesRequest(domainId: domainId, anchor: anchor))
        )
        guard case .changes(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return (response.anchor, response.changes)
    }

    public func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        flags: Item.Flags? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws(AgentError) {
        let reply = try await perform(
            .setAttributes(
                SetAttributesRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue,
                    flags: flags,
                    accessTime: accessTime,
                    modifyTime: modifyTime
                )
            )
        )
        guard case .setAttributes = reply else {
            throw AgentError.unexpectedResponse
        }
    }

    public func createSymlink(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        target: String
    ) async throws(AgentError) -> Item {
        let reply = try await perform(
            .createSymlink(
                CreateSymlinkRequest(
                    domainId: domainId,
                    parentId: parentId.rawValue,
                    name: name,
                    target: target
                )
            )
        )
        guard case .createSymlink(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return response.item
    }

    public func createDirectory(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        mode: mode_t = 0o700,
        ifExists: OnExists = .fail
    ) async throws(AgentError) -> Item {
        let reply = try await perform(
            .createDirectory(
                CreateDirectoryRequest(
                    domainId: domainId,
                    parentId: parentId.rawValue,
                    name: name,
                    mode: mode,
                    ifExists: ifExists
                )
            )
        )
        guard case .createDirectory(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return response.item
    }

    public func move(
        _ itemId: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String
    ) async throws(AgentError) {
        let reply = try await perform(
            .move(
                MoveRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue,
                    newParentId: newParentId.rawValue,
                    newName: newName
                )
            )
        )
        guard case .move = reply else {
            throw AgentError.unexpectedResponse
        }
    }

    public func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(AgentError) {
        let reply = try await perform(
            .removeFile(
                RemoveFileRequest(domainId: domainId, itemId: itemId.rawValue)
            )
        )
        guard case .removeFile = reply else {
            throw AgentError.unexpectedResponse
        }
    }

    public func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws(AgentError) {
        let reply = try await perform(
            .removeDirectory(
                RemoveDirectoryRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue
                )
            )
        )
        guard case .removeDirectory = reply else {
            throw AgentError.unexpectedResponse
        }
    }

    public func limits() async throws(AgentError) -> Limits {
        let reply = try await perform(
            .limits(
                LimitsRequest(
                    domainId: domainId
                )
            )
        )
        guard case .limits(let response) = reply else {
            throw AgentError.unexpectedResponse
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
    ) async throws(AgentError) -> Item {
        let stagedUrl = sharedUrl.appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: file, to: stagedUrl)
        } catch {
            throw AgentError(from: error)
        }
        defer { try? FileManager.default.moveItem(at: stagedUrl, to: file) }

        progress.kind = .file
        progress.fileOperationKind = .uploading

        let sync = XPCProgressSubscriber(progress: progress)
        let reply = try await perform(
            .upload(
                UploadRequest(
                    domainId: domainId,
                    parentId: parentId.rawValue,
                    name: name,
                    file: stagedUrl,
                    flags: flags,
                    chunkSize: chunkSize,
                    progressEndpoint: sync.endpoint
                )
            )
        )
        guard case .upload(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return response.item
    }

    public func download(
        itemId: NSFileProviderItemIdentifier,
        chunkSize: UInt64 = Limits.defaultBufferSize,
        progress: Progress
    ) async throws(AgentError) -> (URL, Item) {
        progress.kind = .file
        progress.fileOperationKind = .downloading

        let sync = XPCProgressSubscriber(progress: progress)
        let reply = try await perform(
            .download(
                DownloadRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue,
                    chunkSize: chunkSize,
                    progressEndpoint: sync.endpoint
                )
            )
        )
        guard case .download(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return (response.url, response.item)
    }

    public func stream(
        itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>,
        progress: Progress
    ) async throws(AgentError) -> (URL, Range<UInt64>) {
        progress.kind = .file
        progress.fileOperationKind = .downloading

        let sync = XPCProgressSubscriber(progress: progress)
        let reply = try await perform(
            .stream(
                StreamRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue,
                    range: range,
                    progressEndpoint: sync.endpoint
                )
            )
        )
        guard case .stream(let response) = reply else {
            throw AgentError.unexpectedResponse
        }
        return (response.url, response.range)
    }
}
