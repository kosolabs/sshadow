import AgentKit
import Common
import FileProvider
import Foundation
import SwiftData
import XPC

private let logger = Logger(category: "TestData")

class TestSandbox {
    let id: UUID
    let name: String
    let host: String
    let port: UInt16
    let user: String
    let root: URL
    let mount: URL
    let shared: URL
    let domain: NSFileProviderDomain
    private var listener: XPCListener?

    init() {
        self.id = UUID()
        self.name = "test"
        self.host = "localhost"
        self.port = 2248
        self.user = NSUserName()

        self.root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        self.mount = self.root.appending(path: "mount")
        try? FileManager.default.createDirectory(
            at: self.mount,
            withIntermediateDirectories: true
        )
        self.shared = self.root.appending(path: "shared")
        try? FileManager.default.createDirectory(
            at: self.shared,
            withIntermediateDirectories: true
        )

        self.domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(
                rawValue: id.uuidString
            ),
            displayName: "Test"
        )
    }

    deinit {
        self.listener?.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    func getConnectionConfig() throws -> ConnectionConfig {
        try ConnectionConfig(
            id: id,
            name: name,
            host: host,
            port: port,
            user: user,
            path: mount.path(),
            authMethod: .privateKey(
                base64PrivateKey: getBase64PrivateKey(),
                passphrase: nil
            ),
        )
    }

    func getBase64PrivateKey() throws -> String {
        return try String(contentsOf: getPrivateKeyUrl(), encoding: .utf8)
    }

    func getPrivateKeyUrl() throws -> URL {
        let bundle = Bundle(for: BundleMarker.self)

        guard
            let url = bundle.url(forResource: "id_ed25519", withExtension: nil)
        else {
            throw NSError(
                domain: "TestData",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to locate id_ed25519 in bundle"
                ]
            )
        }

        return url
    }

    func getAgentClient() async throws -> AgentClient {
        let appDb = try AppDB.open(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let profile = try ConnectionProfile(
            id: id,
            name: name,
            enabled: true,
            host: host,
            port: port,
            user: user,
            path: mount.path(),
            authMethod: .privateKey,
            bookmark: getPrivateKeyUrl().bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        )

        try await appDb.upsert(profile: profile)

        let listener = Agent.createAnonymous(
            appDb: appDb,
            domainDbConfig: ModelConfiguration(isStoredInMemoryOnly: true),
            sharedUrl: shared
        )
        self.listener = listener

        let session = try! XPCSession(endpoint: listener.endpoint)
        let agent = AgentClient(
            domainId: id,
            session: session,
            sharedUrl: shared
        )

        var folders: [NSFileProviderItemIdentifier] = [.rootContainer]
        while !folders.isEmpty {
            let folder = folders.removeFirst()
            let items = try await agent.list(for: folder)
            for item in items {
                if item.kind == .folder, (item.permissions ?? 0) & 0o400 != 0 {
                    folders.append(item.id)
                }
            }
        }

        return agent
    }

    func getUrl(path: String) -> URL {
        mount.appending(path: path)
    }

    func exists(path: String) -> Bool {
        FileManager.default.fileExists(at: getUrl(path: path))
    }

    @discardableResult
    func removeItem(path: String) throws -> URL {
        let url = getUrl(path: path)
        if FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }

    @discardableResult
    func createFolder(
        path: String,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        let folder = getUrl(path: path)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        var attributes: [FileAttributeKey: Any] = [:]

        if let permissions {
            attributes[FileAttributeKey.posixPermissions] = permissions
        }

        if let modifyDate {
            attributes[FileAttributeKey.modificationDate] = modifyDate
        }

        if !attributes.isEmpty {
            try FileManager.default.setAttributes(
                attributes,
                ofItemAtPath: folder.path()
            )
        }

        return folder
    }

    @discardableResult
    func createSymlink(
        path: String,
        target: String
    ) throws -> URL {
        let link = getUrl(path: path)
        let folder = link.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(
            atPath: link.path(),
            withDestinationPath: target
        )

        return link
    }

    @discardableResult
    func createFile(
        path: String,
        contents: String = "",
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        guard let data = contents.data(using: .utf8) else {
            throw NSError(
                domain: "TestData",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to encode content"
                ]
            )
        }

        return try createFile(
            path: path,
            data: data,
            permissions: permissions,
            modifyDate: modifyDate
        )
    }

    @discardableResult
    func createFile(
        path: String,
        data: Data,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        let file = getUrl(path: path)
        let folder = file.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        FileManager.default.createFile(atPath: file.path(), contents: data)

        var attributes: [FileAttributeKey: Any] = [:]

        if let permissions {
            attributes[FileAttributeKey.posixPermissions] = permissions
        }

        if let modifyDate {
            attributes[FileAttributeKey.modificationDate] = modifyDate
        }

        if !attributes.isEmpty {
            try FileManager.default.setAttributes(
                attributes,
                ofItemAtPath: file.path()
            )
        }

        return file
    }
}

enum TestData {
    static let id = UUID()
    static let name = "test"
    static let host = "localhost"
    static let port: UInt16 = 2248
    static let user = NSUserName()
    static let mount: URL = {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        logger.info("Test server mount path: \(url.path())")
        return url
    }()
    static let sharedUrl: URL = {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        logger.info("Test shared path: \(url.path())")
        return url
    }()
    static let domain = NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier(
            rawValue: id.uuidString
        ),
        displayName: "Test"
    )

    private static func createAppDb() async throws -> AppDB {
        let db = try AppDB.open(
            config: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let profile = try ConnectionProfile(
            id: id,
            name: name,
            enabled: true,
            host: host,
            port: port,
            user: user,
            path: mount.path(),
            authMethod: .privateKey,
            bookmark: getPrivateKeyUrl().bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        )

        try await db.upsert(profile: profile)
        return db
    }

    static func getConnectionConfig(
        id: UUID = id,
        url: URL = mount
    ) throws -> ConnectionConfig {
        try ConnectionConfig(
            id: id,
            name: name,
            host: host,
            port: port,
            user: user,
            path: url.path(),
            authMethod: .privateKey(
                base64PrivateKey: getBase64PrivateKey(),
                passphrase: nil
            ),
        )
    }

    static func getBase64PrivateKey() throws -> String {
        return try String(contentsOf: getPrivateKeyUrl(), encoding: .utf8)
    }

    static func getPrivateKeyUrl() throws -> URL {
        let bundle = Bundle(for: BundleMarker.self)

        guard
            let url = bundle.url(forResource: "id_ed25519", withExtension: nil)
        else {
            throw NSError(
                domain: "TestData",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to locate id_ed25519 in bundle"
                ]
            )
        }

        return url
    }

    private static var testListener: XPCListener?

    static func getAgentClient(id: UUID = id) async throws -> AgentClient {
        let appDb = try await createAppDb()
        let listener = Agent.createAnonymous(
            appDb: appDb,
            domainDbConfig: ModelConfiguration(isStoredInMemoryOnly: true),
            sharedUrl: sharedUrl
        )
        testListener = listener
        let session = try! XPCSession(endpoint: listener.endpoint)
        let agent = AgentClient(
            domainId: id,
            session: session,
            sharedUrl: sharedUrl
        )

        var folders: [NSFileProviderItemIdentifier] = [.rootContainer]
        while !folders.isEmpty {
            let folder = folders.removeFirst()
            let items = try await agent.list(for: folder)
            for item in items {
                if item.kind == .folder, (item.permissions ?? 0) & 0o400 != 0 {
                    folders.append(item.id)
                }
            }
        }

        return agent
    }

    static func getUrl(path: String) -> URL {
        mount.appending(path: path)
    }

    static func exists(path: String) -> Bool {
        FileManager.default.fileExists(at: getUrl(path: path))
    }

    @discardableResult
    static func removeItem(path: String) throws -> URL {
        let url = getUrl(path: path)
        if FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }

    @discardableResult
    static func createFolder(
        path: String,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        let folder = getUrl(path: path)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        var attributes: [FileAttributeKey: Any] = [:]

        if let permissions {
            attributes[FileAttributeKey.posixPermissions] = permissions
        }

        if let modifyDate {
            attributes[FileAttributeKey.modificationDate] = modifyDate
        }

        if !attributes.isEmpty {
            try FileManager.default.setAttributes(
                attributes,
                ofItemAtPath: folder.path()
            )
        }

        return folder
    }

    @discardableResult
    static func createSymlink(
        path: String,
        target: String
    ) throws -> URL {
        let link = getUrl(path: path)
        let folder = link.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(
            atPath: link.path(),
            withDestinationPath: target
        )

        return link
    }

    @discardableResult
    static func createFile(
        path: String,
        contents: String,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        guard let data = contents.data(using: .utf8) else {
            throw NSError(
                domain: "TestData",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to encode content"
                ]
            )
        }

        return try createFile(
            path: path,
            data: data,
            permissions: permissions,
            modifyDate: modifyDate
        )
    }

    @discardableResult
    static func createFile(
        path: String,
        data: Data,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        let file = getUrl(path: path)
        let folder = file.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        FileManager.default.createFile(atPath: file.path(), contents: data)

        var attributes: [FileAttributeKey: Any] = [:]

        if let permissions {
            attributes[FileAttributeKey.posixPermissions] = permissions
        }

        if let modifyDate {
            attributes[FileAttributeKey.modificationDate] = modifyDate
        }

        if !attributes.isEmpty {
            try FileManager.default.setAttributes(
                attributes,
                ofItemAtPath: file.path()
            )
        }

        return file
    }
}

private class BundleMarker {}
