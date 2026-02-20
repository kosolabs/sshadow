import Common
import Foundation
import OSLog

let logger = getLogger(category: "TestData")

struct TestData {
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
        logger.notice("Test server mount path: \(url.path())")
        return url
    }()

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

    static func getTestURL(path: String) -> URL {
        mount.appending(path: path)
    }

    static func removeTestItem(path: String) throws {
        let url = getTestURL(path: path)
        if FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.removeItem(at: url)
        }
    }

    @discardableResult
    static func createTestFolder(path: String) throws -> URL {
        let folder = getTestURL(path: path)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder
    }

    @discardableResult
    static func createTestFile(path: String, contents: String) throws -> URL {
        guard let data = contents.data(using: .utf8) else {
            throw NSError(
                domain: "TestData",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to encode content"
                ]
            )
        }

        return try createTestFile(path: path, data: data)
    }

    @discardableResult
    static func createTestFile(path: String, data: Data) throws -> URL {
        let file = getTestURL(path: path)
        let folder = file.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        FileManager.default.createFile(atPath: file.path(), contents: data)

        return file
    }
}

private class BundleMarker {}
