import Common
import FileProvider
import Foundation
import SwiftData
import Testing
import XPC

@testable import CoreKit

private let logger = Logger(category: "TestData")

enum RelativeTo {
    case mount
    case shared
}

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

    private var connection: NSXPCConnection?
    private var _supervisor: SessionSupervisor?
    private var _client: CoreClient?

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

        self.domain = NSFileProviderDomain(id: id, displayName: "Test")
    }

    deinit {
        self.connection?.invalidate()
        try? FileManager.default.removeItem(at: root)
    }

    var config: ConnectionConfig {
        get throws {
            try ConnectionConfig(
                id: id,
                name: name,
                host: host,
                port: port,
                user: user,
                path: mount.path(),
                authMethod: .privateKey(
                    base64PrivateKey: base64PrivateKey,
                    passphrase: nil
                ),
            )
        }
    }

    var base64PrivateKey: String {
        get throws {
            try String(contentsOf: privateKeyUrl, encoding: .utf8)
        }
    }

    var privateKeyUrl: URL {
        get throws {
            try #require(
                Bundle(for: BundleMarker.self).url(
                    forResource: "id_ed25519",
                    withExtension: nil
                ),
                "Failed to locate id_ed25519 in bundle"
            )
        }
    }

    var supervisor: SessionSupervisor {
        get async throws {
            if let _supervisor {
                return _supervisor
            }

            let memoryOnlyConfig = ModelConfiguration(
                isStoredInMemoryOnly: true
            )

            let config = try config
            let supervisor = SessionSupervisor(
                config: config,
                domainDbConfig: memoryOnlyConfig,
                sharedUrl: shared,
                signal: { _ in },
                transfers: Transfers(),
                pollInterval: nil,
                ext: config.domain
            )

            try await supervisor.connectForTests()
            self._supervisor = supervisor
            return supervisor
        }
    }

    func poll() async throws {
        try await supervisor.withSession { try await $0.poll() }
    }

    var client: CoreClient {
        get async throws {
            if let _client {
                return _client
            }

            let service = CoreService(supervisor: try await supervisor)
            let client = CoreClient(domain: domain, sharedUrl: shared)

            let connection = NSXPCConnection(
                listenerEndpoint: try client.makeListenerEndpoint()
            )
            connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
            connection.exportedObject = service
            connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
            connection.resume()
            self.connection = connection

            let ext = connection.remoteObjectProxy as! ExtXPC
            await ext.attach()

            var folders: [NSFileProviderItemIdentifier] = [.rootContainer]
            while !folders.isEmpty {
                let folder = folders.removeFirst()
                let items = try await client.list(for: folder)
                for item in items {
                    if item.kind == .folder,
                        let flags = item.flags,
                        flags.contains(.executable)
                    {
                        folders.append(item.id)
                    }
                }
            }

            // Prevent suspend when the client is eventually torn down
            await ext.detach()

            self._client = client
            return client
        }
    }

    func getUrl(for path: String, relativeTo: RelativeTo = .mount) -> URL {
        switch relativeTo {
        case .mount:
            mount.appending(path: path)
        case .shared:
            shared.appending(path: path)
        }
    }

    func exists(at path: String) -> Bool {
        FileManager.default.fileExists(at: getUrl(for: path))
    }

    func attributes(of path: String) throws -> NSDictionary {
        try FileManager.default.attributes(of: getUrl(for: path))
            as NSDictionary
    }

    func size(of path: String) throws -> UInt64 {
        try attributes(of: path).fileSize()
    }

    func permissions(of path: String) throws -> mode_t {
        UInt16(try attributes(of: path).filePosixPermissions())
    }

    func modifyDate(of path: String) throws -> Date {
        guard let date = try attributes(of: path).fileModificationDate() else {
            throw NSError(
                domain: "FileManagerExtensions",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to get modification date for \(path)"
                ]
            )
        }
        return date
    }

    func accessDate(of path: String) throws -> Date {
        let url = getUrl(for: path)
        let values = try url.resourceValues(forKeys: [.contentAccessDateKey])
        guard let date = values.contentAccessDate else {
            throw NSError(
                domain: "FileManagerExtensions",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to get access date for \(path)"
                ]
            )
        }
        return date
    }

    func target(of path: String) throws -> String {
        try FileManager.default
            .destinationOfSymbolicLink(at: getUrl(for: path))
    }

    func contents(of path: String) throws -> String {
        try String(contentsOf: getUrl(for: path), encoding: .utf8)
    }

    func data(at path: String) throws -> Data {
        try Data(contentsOf: getUrl(for: path))
    }

    func move(
        from src: String,
        to dest: String,
        relativeTo: RelativeTo = .mount
    ) throws {
        let srcUrl = getUrl(for: src, relativeTo: relativeTo)
        let destUrl = getUrl(for: dest, relativeTo: relativeTo)
        try FileManager.default.moveItem(at: srcUrl, to: destUrl)
    }

    @discardableResult
    func removeItem(at path: String) throws -> URL {
        let url = getUrl(for: path)
        if FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }

    func touch(
        _ path: String,
        relativeTo: RelativeTo = .mount,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws {
        try touch(
            getUrl(for: path, relativeTo: relativeTo),
            permissions: permissions,
            modifyDate: modifyDate
        )
    }

    private func touch(
        _ url: URL,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws {
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
                ofItemAtPath: url.path()
            )
        }
    }

    private func withAncestors(
        for url: URL,
        modifyDate: Date? = nil,
        perform operation: () throws -> Void
    ) throws {
        let parent = url.deletingLastPathComponent()
        var ancestors: [URL] = []
        var curr = parent
        while !FileManager.default.fileExists(atPath: curr.path()) {
            ancestors.append(curr)
            curr = curr.deletingLastPathComponent()
        }
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        try operation()

        for ancestor in ancestors.reversed() {
            try touch(ancestor, modifyDate: modifyDate)
        }
    }

    @discardableResult
    func createFolder(
        at path: String,
        relativeTo: RelativeTo = .mount,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        let folder = getUrl(for: path, relativeTo: relativeTo)
        try withAncestors(for: folder, modifyDate: modifyDate) {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: false
            )
            try touch(folder, permissions: permissions, modifyDate: modifyDate)
        }
        return folder
    }

    @discardableResult
    func createSymlink(
        at path: String,
        relativeTo: RelativeTo = .mount,
        target: String,
        modifyDate: Date? = nil
    ) throws -> URL {
        let link = getUrl(for: path, relativeTo: relativeTo)
        try withAncestors(for: link, modifyDate: modifyDate) {
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(
                atPath: link.path(),
                withDestinationPath: target
            )
        }
        return link
    }

    @discardableResult
    func createFile(
        at path: String,
        relativeTo: RelativeTo = .mount,
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
            at: path,
            relativeTo: relativeTo,
            data: data,
            permissions: permissions,
            modifyDate: modifyDate
        )
    }

    @discardableResult
    func createFile(
        at path: String,
        relativeTo: RelativeTo = .mount,
        data: Data,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        let file = getUrl(for: path, relativeTo: relativeTo)
        try withAncestors(for: file, modifyDate: modifyDate) {
            FileManager.default.createFile(atPath: file.path(), contents: data)
            try touch(file, permissions: permissions, modifyDate: modifyDate)
        }
        return file
    }
}

private class BundleMarker {}
