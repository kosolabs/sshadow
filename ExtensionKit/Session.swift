import Common
import FileProvider
import SwiftLibSSH

private let logger = Logger(category: "Session")

class Session {
    static var agentClientFactory: (UUID) -> AgentClient = { domainId in
        AgentClient(domainId: domainId)
    }

    let domain: NSFileProviderDomain
    let config: ConnectionConfig
    let ssh: SSHClient
    let sftp: SFTPClient
    let db: DomainDB
    let agent: AgentClient

    var name: String {
        domain.displayName
    }

    init(
        domain: NSFileProviderDomain,
        config: ConnectionConfig,
        ssh: SSHClient,
        sftp: SFTPClient,
        db: DomainDB,
        agent: AgentClient? = nil
    ) {
        self.domain = domain
        self.config = config
        self.ssh = ssh
        self.sftp = sftp
        self.db = db
        self.agent = agent ?? Self.agentClientFactory(config.id)
    }

    func id(of identifier: NSFileProviderItemIdentifier) async -> String {
        await "FPItemID(\(identifier.desc), \(db.path(for: identifier)))"
    }

    func name(
        of identifier: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await agent.name(of: identifier)
    }

    func child(
        of parent: NSFileProviderItemIdentifier = .rootContainer,
        path: String,
        ifNotExists: DomainDB.OnNotExists = .create
    ) async throws -> NSFileProviderItemIdentifier {
        try await agent.child(of: parent, path: path, ifNotExists: ifNotExists)
    }

    func parent(
        of identifier: NSFileProviderItemIdentifier
    ) async throws -> NSFileProviderItemIdentifier {
        try await agent.parent(of: identifier)
    }

    func path(
        for identifier: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await agent.path(for: identifier)
    }

    func path(
        for name: String,
        parentId: NSFileProviderItemIdentifier
    ) async throws -> String {
        try await agent.path(for: name, parentId: parentId)
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
    ) async throws -> Item {
        try await Item(
            domainName: domain.displayName,
            itemIdentifier: identifier,
            parentItemIdentifier: parent(of: identifier),
            filename: name(of: identifier),
            itemAttributes: attributes(for: identifier)
        )
    }

    func attributes(
        for identifier: NSFileProviderItemIdentifier
    ) async throws -> SFTPAttributes {
        try await agent.attributes(for: identifier)
    }

    func exists(for identifier: NSFileProviderItemIdentifier) async -> Bool {
        do {
            _ = try await agent.attributes(for: identifier)
            return true
        } catch {
            return false
        }
    }

    func setAttributes(
        for identifier: NSFileProviderItemIdentifier,
        permissions: mode_t? = nil,
        accessTime: Date? = nil,
        modifyTime: Date? = nil
    ) async throws {
        try await agent.setAttributes(
            for: identifier,
            permissions: permissions,
            accessTime: accessTime,
            modifyTime: modifyTime
        )
    }

    func move(
        _ id: NSFileProviderItemIdentifier,
        toParent newParentId: NSFileProviderItemIdentifier,
        name newName: String,
        ifParentNotExists: OnParentNotExists = .fail
    ) async throws {
        try await agent.move(
            id,
            toParent: newParentId,
            name: newName,
            ifParentNotExists: ifParentNotExists
        )
    }

    func removeFile(
        for identifier: NSFileProviderItemIdentifier
    ) async throws {
        try await agent.removeFile(for: identifier)
    }

    func createDirectory(
        for identifier: NSFileProviderItemIdentifier,
        mode: mode_t = 0o700,
        ifExists: OnExists = .fail
    ) async throws {
        try await agent.createDirectory(
            for: identifier,
            mode: mode,
            ifExists: ifExists
        )
    }

    func removeDirectory(
        for identifier: NSFileProviderItemIdentifier
    ) async throws {
        try await agent.removeDirectory(for: identifier)
    }

    func withFile<T: Sendable>(
        for identifier: NSFileProviderItemIdentifier,
        accessType: AccessType,
        mode: mode_t = 0o600,
        perform: @Sendable (SFTPFile) async throws -> T
    ) async throws -> T {
        await logger.info("With \(accessType) file \(id(of: identifier))")
        return try await mapError(with: identifier) {
            try await sftp.withSftpFile(
                atPath: path(for: identifier),
                accessType: accessType,
                mode: mode,
                perform: perform
            )
        }
    }

    func withDirectory<T: Sendable>(
        for identifier: NSFileProviderItemIdentifier,
        perform: @Sendable (SFTPDirectory) async throws -> T
    ) async throws -> T {
        await logger.info("With directory \(id(of: identifier))")
        return try await mapError(with: identifier) {
            try await sftp.withDirectory(
                atPath: path(for: identifier),
                perform: perform
            )
        }
    }

    func stream(
        for identifier: NSFileProviderItemIdentifier,
        range: NSRange,
        alignment: Int,
        fileSize: UInt64,
        onData: (Data) throws -> Void
    ) async throws -> (URL, NSRange) {
        let itemRef = await id(of: identifier)

        guard SSHChunk.size % UInt64(alignment) == 0 else {
            throw NSFileProviderError(
                .cannotSynchronize,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Alignment \(alignment) is not a divisor of chunk size \(SSHChunk.size)"
                ]
            )
        }

        let chunkRange = SSHChunk.chunkRange(for: range.asRange())

        logger.info("Stream \(itemRef)[\(chunkRange)](\(range))")

        let cacheURL = FileManager.default.temporaryDirectory
            .appending(path: "chunks-\(identifier.rawValue)")

        for chunkIndex in chunkRange {
            if await db.isChunkCached(for: identifier, index: chunkIndex) {
                logger.debug("Cache hit \(itemRef)[\(chunkIndex)]")
                continue
            }

            let bytes = SSHChunk.byteRange(for: chunkIndex, fileSize: fileSize)
            guard !bytes.isEmpty else { continue }

            if !FileManager.default.fileExists(atPath: cacheURL.path()) {
                FileManager.default.createFile(
                    atPath: cacheURL.path(),
                    contents: nil
                )
            }

            let handle = try FileHandle(forWritingTo: cacheURL)
            defer { try? handle.close() }

            try await withFile(for: identifier, accessType: .readOnly) { file in
                for try await data in file.stream(
                    offset: bytes.offset,
                    length: bytes.length
                ) {
                    try handle.write(contentsOf: data)
                    try onData(data)
                }
            }

            try await db.recordChunk(for: identifier, index: chunkIndex)
            logger.debug("Cached \(itemRef)[\(chunkIndex)]")
        }

        let byteRange = SSHChunk.byteRange(for: chunkRange, fileSize: fileSize)
        logger.info("Streamed \(itemRef)[\(chunkRange)](\(byteRange))")
        return (cacheURL, byteRange.asNSRange())
    }

    func enumerateItems(
        for identifier: NSFileProviderItemIdentifier,
        yield: @Sendable ([any NSFileProviderItemProtocol]) -> Void
    ) async throws {
        try await withDirectory(for: identifier) { dir in
            for try await attrs in dir {
                if let name = attrs.name {
                    let childId = try await child(
                        of: identifier,
                        path: name
                    )
                    let item = Item(
                        domainName: self.name,
                        itemIdentifier: childId,
                        parentItemIdentifier: identifier,
                        filename: name,
                        itemAttributes: attrs
                    )
                    yield([item])
                }
            }
        }
    }

    func mapError<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch SSHError.sftpError(.noSuchFile, _) {
            logger.fault("No such file")
            throw NSFileProviderError(.noSuchItem)
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            logger.fault("File already exists")
            throw NSFileProviderError(.filenameCollision)
        }
    }

    func mapError<T>(
        with identifier: NSFileProviderItemIdentifier,
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch SSHError.sftpError(.noSuchFile, _) {
            await logger.debug("\(id(of: identifier)) doesn't exist")
            throw NSError.fileProviderErrorForNonExistentItem(
                withIdentifier: identifier
            )
        } catch SSHError.sftpError(.fileAlreadyExists, _) {
            await logger.debug("\(id(of: identifier)) already exists")
            throw NSFileProviderError(.filenameCollision)
        }
    }
}
