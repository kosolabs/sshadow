import Common
import FileProvider
import Testing
import UniformTypeIdentifiers

@testable import Extension

struct ExtensionTests {
    private func getExtension(id: UUID = UUID()) throws -> Extension {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(
                rawValue: id.uuidString
            ),
            displayName: "test"
        )
        let userInfo = try TestData.getUserInfo(id: id)
        domain.userInfo = try userInfo.toDictionary()
        return Extension(domain: domain)
    }

    @Test func initializeValidConfigSucceeds() throws {
        let ext = try getExtension()
        let actualConfig = ext.config

        let id = try #require(actualConfig?.id)
        let expectedConfig = try TestData.getConnectionConfig(id: id)

        #expect(actualConfig == expectedConfig)
    }

    @Test func itemForFileSucceeds() async throws {
        let ext = try getExtension()

        let path = "item/file.txt"
        let contents = "Hello, World!"
        try TestData.createTestFile(path: path, contents: contents)

        let item = try await ext.item(for: .rootContainer.child(name: path))

        #expect(item.filename == "file.txt")
        #expect(item.contentType == .text)
        #expect(item.documentSize??.intValue == contents.count)
    }

    @Test func itemForFolderSucceeds() async throws {
        let ext = try getExtension()

        let path = "item"
        try TestData.createTestFolder(path: path)

        let item = try await ext.item(for: .rootContainer.child(name: path))

        #expect(item.filename == "item")
        #expect(item.contentType == .folder)
    }

    @Test func itemForRootSucceeds() async throws {
        let ext = try getExtension()

        let item = try await ext.item(for: .rootContainer)

        #expect(item.filename == "NSFileProviderRootContainerItemIdentifier")
        #expect(item.contentType == .folder)
    }

    @Test func itemForMissingFileThrows() async throws {
        let ext = try getExtension()

        let path = "item/missing.txt"

        await #expect(throws: NSFileProviderError(.noSuchItem).self) {
            try await ext.item(for: .rootContainer.child(name: path))
        }
    }

    @Test func itemForInvalidConfigThrows() async throws {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: "id"),
            displayName: "test"
        )
        let ext = Extension(domain: domain)

        await #expect(throws: NSFileProviderError(.notAuthenticated).self) {
            try await ext.item(for: .rootContainer)
        }
    }

    @Test func itemForUnreachableServerThrows() async throws {
        let id = UUID()
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: id.uuidString),
            displayName: "test"
        )
        let userInfo = try UserInfo(
            id: id,
            name: "unreachable",
            host: "unreachable",
            port: 22,
            user: NSUserName(),
            path: "",
            authMethod: .privateKey(
                bookmark: TestData.getPrivateKeyURL().bookmarkData()
            )
        )
        domain.userInfo = try userInfo.toDictionary()
        let ext = Extension(domain: domain)

        await #expect(throws: NSFileProviderError(.serverUnreachable).self) {
            try await ext.item(for: .rootContainer.child(name: "unreachable"))
        }
    }

    @Test func fetchContentsOfSmallFile() async throws {
        let ext = try getExtension()

        let path = "fetch-contents/small-file.txt"
        let contents = "Hello, World!"
        try TestData.createTestFile(path: path, contents: contents)

        let progress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: .rootContainer.child(name: path),
            version: nil,
            request: NSFileProviderRequest(),
            progress: progress
        )

        #expect(item.filename == "small-file.txt")
        #expect(item.contentType == .text)
        #expect(item.documentSize??.intValue == contents.count)

        let actualContents = try String(contentsOf: url, encoding: .utf8)
        #expect(actualContents == contents)
    }

    @Test func fetchContentsOfLargeFile() async throws {
        let ext = try getExtension()

        let path = "fetch-contents/large-file.txt"
        let contents = String(repeating: "A", count: 10_000_000)
        try TestData.createTestFile(path: path, contents: contents)

        let progress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: .rootContainer.child(name: path),
            version: nil,
            request: NSFileProviderRequest(),
            progress: progress
        )

        #expect(item.filename == "large-file.txt")
        #expect(item.contentType == .text)
        #expect(item.documentSize??.intValue == contents.count)

        let actualContents = try String(contentsOf: url, encoding: .utf8)
        #expect(actualContents == contents)
    }

    @Test func fetchContentsWithCancellation() async throws {
        let ext = try getExtension()

        let path = "fetch-contents/cancellable-file.txt"
        let contents = String(repeating: "A", count: 10_000_000)
        try TestData.createTestFile(path: path, contents: contents)

        let progress = Progress()

        let fetchTask = Task {
            try await ext.fetchContents(
                for: .rootContainer.child(name: path),
                version: nil,
                request: NSFileProviderRequest(),
                progress: progress
            )
        }

        progress.cancel()

        await #expect(throws: CocoaError(.userCancelled).self) {
            try await fetchTask.value
        }
    }
}

extension Extension {
    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest = NSFileProviderRequest(),
    ) async throws -> NSFileProviderItem {
        try await withCheckedThrowingContinuation { continuation in
            _ = self.item(for: identifier, request: request) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion? = nil,
        request: NSFileProviderRequest = NSFileProviderRequest(),
        progress: Progress,
    ) async throws -> (URL, NSFileProviderItem) {
        try await withCheckedThrowingContinuation { continuation in
            let operationProgress = self.fetchContents(
                for: itemIdentifier,
                version: requestedVersion,
                request: request
            ) { url, item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url, let item {
                    continuation.resume(returning: (url, item))
                }
            }

            progress.addChild(operationProgress, withPendingUnitCount: 1)
        }
    }
}
