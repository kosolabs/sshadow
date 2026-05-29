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
        logger.debug("Opening agent: \(session)")
        self.domainId = domainId
        self.session = session
        self.sharedUrl = sharedUrl
    }

    deinit {
        logger.debug("Closing agent: \(session)")
        session.cancel(reason: "AgentClient deallocated")
    }

    private func perform(
        _ request: AgentRequest
    ) async throws -> AgentResponse {
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
        } catch let error as XPCRichError {
            logger.error("XPC failure: \(error)")
            throw NSFileProviderError(.serverUnreachable)
        } catch {
            logger.error("Request failed: \(error)")
            throw error
        }
    }

    public func initDomain() async throws {
        let reply = try await perform(
            .initDomain(InitDomainRequest(domainId: domainId))
        )
        guard case .initDomain = reply else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func deinitDomain() async throws {
        let reply = try await perform(
            .deinitDomain(DeinitDomainRequest(domainId: domainId))
        )
        guard case .deinitDomain = reply else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func name(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        let reply = try await perform(
            .name(NameRequest(domainId: domainId, itemId: itemId.rawValue))
        )
        guard case .name(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
        }
        return response.name
    }

    public func child(
        of parentId: NSFileProviderItemIdentifier = .rootContainer,
        path: String
    ) async throws -> NSFileProviderItemIdentifier {
        let reply = try await perform(
            .child(
                ChildRequest(
                    domainId: domainId,
                    parentId: parentId.rawValue,
                    path: path
                )
            )
        )
        guard case .child(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
        }
        return NSFileProviderItemIdentifier(response.itemId)
    }

    public func parent(
        of itemId: NSFileProviderItemIdentifier
    ) async throws -> NSFileProviderItemIdentifier {
        let reply = try await perform(
            .parent(
                ParentRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue
                )
            )
        )
        guard case .parent(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
        }
        return NSFileProviderItemIdentifier(response.itemId)
    }

    public func path(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> String {
        let reply = try await perform(
            .pathForItem(
                PathForItemRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue
                )
            )
        )
        guard case .path(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
        }
        return response.path
    }

    public func path(
        for name: String,
        parentId: NSFileProviderItemIdentifier
    ) async throws -> String {
        let reply = try await perform(
            .pathForChild(
                PathForChildRequest(
                    domainId: domainId,
                    name: name,
                    parentId: parentId.rawValue
                )
            )
        )
        guard case .path(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
        }
        return response.path
    }

    public func item(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> Item {
        let reply = try await perform(
            .item(
                ItemRequest(domainId: domainId, itemId: itemId.rawValue)
            )
        )
        guard case .item(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
        }
        return response.item
    }

    public func list(
        for itemId: NSFileProviderItemIdentifier
    ) async throws -> [Item] {
        let reply = try await perform(
            .list(
                ListRequest(domainId: domainId, itemId: itemId.rawValue)
            )
        )
        guard case .list(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
        }
        return response.fileInfos
    }

    public func setAttributes(
        for itemId: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws {
        let reply = try await perform(
            .setAttributes(
                SetAttributesRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue,
                    permissions: permissions,
                    accessTime: accessTime,
                    modifyTime: modifyTime
                )
            )
        )
        guard case .setAttributes = reply else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func createSymlink(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        target: String
    ) async throws -> Item {
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
            throw CocoaError(.coderInvalidValue)
        }
        return response.item
    }

    public func createDirectory(
        parentId: NSFileProviderItemIdentifier,
        name: String,
        mode: mode_t = 0o700,
        ifExists: OnExists = .fail
    ) async throws -> Item {
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
            throw CocoaError(.coderInvalidValue)
        }
        return response.item
    }

    public func move(
        _ itemId: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String
    ) async throws {
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
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func removeFile(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        let reply = try await perform(
            .removeFile(
                RemoveFileRequest(domainId: domainId, itemId: itemId.rawValue)
            )
        )
        guard case .removeFile = reply else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func removeDirectory(
        for itemId: NSFileProviderItemIdentifier
    ) async throws {
        let reply = try await perform(
            .removeDirectory(
                RemoveDirectoryRequest(
                    domainId: domainId,
                    itemId: itemId.rawValue
                )
            )
        )
        guard case .removeDirectory = reply else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func limits() async throws -> Limits {
        let reply = try await perform(
            .limits(
                LimitsRequest(
                    domainId: domainId
                )
            )
        )
        guard case .limits(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
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
        mode: mode_t,
        chunkSize: UInt64 = Limits.defaultBufferSize,
        progress: Progress
    ) async throws -> Item {
        let stagedUrl = sharedUrl.appending(path: UUID().uuidString)
        try FileManager.default.moveItem(at: file, to: stagedUrl)
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
                    mode: mode,
                    chunkSize: chunkSize,
                    progressEndpoint: sync.endpoint
                )
            )
        )
        guard case .upload(let response) = reply else {
            throw CocoaError(.coderInvalidValue)
        }
        return response.item
    }

    public func download(
        itemId: NSFileProviderItemIdentifier,
        chunkSize: UInt64 = Limits.defaultBufferSize,
        progress: Progress
    ) async throws -> (URL, Item) {
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
            throw CocoaError(.coderInvalidValue)
        }
        return (response.url, response.item)
    }

    public func stream(
        itemId: NSFileProviderItemIdentifier,
        range: Range<UInt64>,
        progress: Progress
    ) async throws -> (URL, Range<UInt64>) {
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
            throw CocoaError(.coderInvalidValue)
        }
        return (response.url, response.range)
    }
}
