import Common
import FileProvider
import Foundation
import SwiftData
import Testing
import XPC

@testable import CoreKit

private let logger = Logger(category: "TestData")

enum TestSandboxError: Error {
    case lchmod
    case lstat
    case utimensat
}

struct NoopXPCBroker: XPCBroker {
    func broker(exporting service: CoreService) async {}
    func teardown() async {}
}

struct NoopExtensionController: ExtensionController {
    func resume() async {}
    func suspend(
        reason: String,
        options: NSFileProviderManager.DisconnectionOptions
    ) async {}
    func remove() async {}
}

extension ConnectionError {
    fileprivate var isTransient: Bool {
        switch self {
        case .connectionRefused, .connectionTimedOut, .unknown:
            true
        case .unknownHost, .invalidPrivateKey, .authenticationFailed,
            .remotePathNotFound, .remotePathNotDirectory, .cancelled:
            false
        }
    }
}

package func withConnectRetries<T>(
    attempts: Int = 5,
    backoff: Duration = .milliseconds(100),
    _ connect: () async throws(ConnectionError) -> T
) async throws(ConnectionError) -> T {
    var delay = backoff
    for attempt in 1..<attempts {
        do {
            return try await connect()
        } catch {
            guard error.isTransient else { throw error }
            logger.notice(
                "Connect attempt \(attempt) of \(attempts) failed: \(error)"
            )
            try? await Task.sleep(for: delay)
            delay *= 2
        }
    }
    return try await connect()
}

package class TestSandbox {
    package enum Location {
        case local
        case group
        case remote
    }

    package let id: UUID
    package let name: String
    package let host: String
    package let port: UInt16
    package let user: String
    package let domain: NSFileProviderDomain
    package let materializedItems = FakeMaterializedItems()
    package let events = Events<ContinuousClock>()

    private let root: URL
    private let local: URL
    private let group: URL
    private let remote: URL

    private var connection: NSXPCConnection?
    private var _supervisor: SessionSupervisor?
    private var _client: CoreClient?

    package init() {
        self.id = UUID()
        self.name = "test"
        self.host = "localhost"
        self.port = 2248
        self.user = NSUserName()

        self.root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        self.local = mkdir("local", in: root)
        self.group = mkdir("group", in: root)
        self.remote = mkdir("remote", in: root)

        self.domain = NSFileProviderDomain(id: id, displayName: "Test")
    }

    deinit {
        self.connection?.invalidate()
        try? FileManager.default.removeItem(at: root)
    }

    package var config: ConnectionConfig {
        get throws {
            try ConnectionConfig(
                id: id,
                name: name,
                host: host,
                port: port,
                user: user,
                path: remote.path(),
                authMethod: .privateKey(
                    contents: privateKeyContents,
                    passphrase: nil
                ),
                ignoreFilenames: [".sshadowignore"],
            )
        }
    }

    package var privateKeyContents: String {
        get throws {
            try String(contentsOf: privateKeyUrl, encoding: .utf8)
        }
    }

    package var privateKeyUrl: URL {
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

    package func sessionProvider() async throws -> Session.Provider {
        let provider = try await Session.provider(
            domainDb: DomainDB.open(
                config: ModelConfiguration(isStoredInMemoryOnly: true)
            ),
            groupUrl: group,
            signalChanges: { _ in },
            retryIgnored: { _ in },
            materializedItems: { [materializedItems] _ in
                try materializedItems.enumerator()
            },
            evictItem: { [materializedItems] _, itemId in
                try materializedItems.evict(itemId)
            },
            transfers: Transfers(),
            events: events
        )
        return { config, handler in
            try await withConnectRetries {
                () async throws(ConnectionError) -> Session in
                try await provider(config, handler)
            }
        }
    }

    package var supervisor: SessionSupervisor {
        get async throws {
            if let _supervisor {
                return _supervisor
            }

            let config = try config

            let supervisor = SessionSupervisor(
                domain: domain,
                pollInterval: nil,
                openSession: try await sessionProvider(),
                xpc: NoopXPCBroker(),
                ext: NoopExtensionController(),
                onStatusChange: { _ in }
            )

            try await supervisor.connect(config: config)

            self._supervisor = supervisor
            return supervisor
        }
    }

    package func pollAll() async throws {
        try await supervisor.withSession { try await $0.pollAll() }
    }

    package var client: CoreClient {
        get async throws {
            if let _client {
                return _client
            }

            let service = CoreService(supervisor: try await supervisor)
            let client = CoreClient(domain: domain, groupUrl: group)

            let connection = NSXPCConnection(
                listenerEndpoint: try client.makeListenerEndpoint()
            )
            connection.exportedInterface = NSXPCInterface(with: CoreXPC.self)
            connection.exportedObject = service
            connection.remoteObjectInterface = NSXPCInterface(with: ExtXPC.self)
            connection.resume()
            self.connection = connection

            try await connection.attach()

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

            try await connection.detach()

            self._client = client
            return client
        }
    }

    package func path(
        for path: String = "",
        in location: Location = .remote
    ) -> String {
        url(for: path, in: location).path()
    }

    package func url(
        for path: String = "",
        in location: Location = .remote
    ) -> URL {
        let base =
            switch location {
            case .local: local
            case .remote: remote
            case .group: group
            }
        return path.isEmpty ? base : base.appending(path: path)
    }

    package func exists(at path: String) -> Bool {
        FileManager.default.fileExists(at: url(for: path))
    }

    package func size(of path: String) throws -> UInt64 {
        try FileManager.default.size(of: url(for: path))
    }

    private func status(of path: String) throws -> stat {
        var status = stat()
        guard lstat(url(for: path).path(), &status) == 0 else {
            throw TestSandboxError.lstat
        }
        return status
    }

    package func permissions(of path: String) throws -> mode_t {
        try status(of: path).st_mode & 0o7777
    }

    package func modifyDate(of path: String) throws -> Date {
        try Date(for: status(of: path).st_mtimespec)
    }

    package func accessDate(of path: String) throws -> Date {
        try Date(for: status(of: path).st_atimespec)
    }

    package func target(of path: String) throws -> String {
        try FileManager.default
            .destinationOfSymbolicLink(at: url(for: path))
    }

    package func contents(of path: String) throws -> String {
        try String(contentsOf: url(for: path), encoding: .utf8)
    }

    package func data(at path: String) throws -> Data {
        try Data(contentsOf: url(for: path))
    }

    package func move(
        from src: String,
        to dest: String,
        in location: Location = .remote
    ) throws {
        let srcUrl = url(for: src, in: location)
        let destUrl = url(for: dest, in: location)
        try FileManager.default.moveItem(at: srcUrl, to: destUrl)
    }

    @discardableResult
    package func removeItem(at path: String) throws -> URL {
        let url = url(for: path)
        if FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }

    package func touch(
        _ path: String,
        in location: Location = .remote,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws {
        try touch(
            url(for: path, in: location),
            permissions: permissions,
            modifyDate: modifyDate
        )
    }

    private func touch(
        _ url: URL,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws {
        let path = url.path()

        if let permissions, lchmod(path, permissions) != 0 {
            throw TestSandboxError.lchmod
        }

        if let modifyDate {
            var times = [
                timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
                timespec(for: modifyDate),
            ]
            if utimensat(AT_FDCWD, path, &times, AT_SYMLINK_NOFOLLOW) != 0 {
                throw TestSandboxError.utimensat
            }
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
    package func createFolder(
        at path: String,
        in location: Location = .remote,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        let folder = url(for: path, in: location)
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
    package func createSymlink(
        at path: String,
        in location: Location = .remote,
        target: String,
        modifyDate: Date? = nil
    ) throws -> URL {
        let link = url(for: path, in: location)
        try withAncestors(for: link, modifyDate: modifyDate) {
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(
                atPath: link.path(),
                withDestinationPath: target
            )
            try touch(link, modifyDate: modifyDate)
        }
        return link
    }

    @discardableResult
    package func createFile(
        at path: String,
        in location: Location = .remote,
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
            in: location,
            data: data,
            permissions: permissions,
            modifyDate: modifyDate
        )
    }

    @discardableResult
    package func createFile(
        at path: String,
        in location: Location = .remote,
        data: Data,
        permissions: mode_t? = nil,
        modifyDate: Date? = nil
    ) throws -> URL {
        let file = url(for: path, in: location)
        try withAncestors(for: file, modifyDate: modifyDate) {
            FileManager.default.createFile(atPath: file.path(), contents: data)
            try touch(file, permissions: permissions, modifyDate: modifyDate)
        }
        return file
    }
}

private func mkdir(_ name: String, in root: URL) -> URL {
    let url = root.appending(path: name)
    try? FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

extension Date {
    init(for ts: timespec) {
        let seconds = Double(ts.tv_sec)
        let nanos = Double(ts.tv_nsec) / 1_000_000_000
        self = Date(timeIntervalSince1970: seconds + nanos)
    }
}

extension timespec {
    init(for date: Date) {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        let nanos = (date.timeIntervalSince1970 - seconds) * 1_000_000_000
        self = timespec(tv_sec: Int(seconds), tv_nsec: Int(nanos))
    }
}

private class BundleMarker {}
