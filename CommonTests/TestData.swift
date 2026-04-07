import Common
import FileProvider
import Foundation
import SwiftData

private let logger = Logger(category: "TestData")

enum TestData {
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
    static let domain = NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier(name),
        displayName: "Test"
    )

    static func getConnectionConfig(
        id: UUID = UUID(),
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

    static func getUserInfo(
        id: UUID = UUID(),
        url: URL = mount,
    ) throws -> UserInfo {
        try UserInfo(
            id: id,
            name: name,
            host: host,
            port: port,
            user: user,
            path: url.path(),
            authMethod: .privateKey(
                bookmark: getPrivateKeyURL().bookmarkData()
            )
        )
    }

    static func getBase64PrivateKey() throws -> String {
        return try String(contentsOf: getPrivateKeyURL(), encoding: .utf8)
    }

    static func getPrivateKeyURL() throws -> URL {
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

    static func getSSHadowDB() throws -> SSHadowDB {
        let schema = Schema([SSHItem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: config)
        return SSHadowDB(modelContainer: container)
    }

    static func getURL(path: String) -> URL {
        mount.appending(path: path)
    }

    @discardableResult
    static func removeItem(path: String) throws -> URL {
        let url = getURL(path: path)
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
        let folder = getURL(path: path)
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
        let file = getURL(path: path)
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
