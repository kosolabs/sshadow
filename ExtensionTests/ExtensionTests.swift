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

    @Test func createItemFolder() async throws {
        let ext = try getExtension()

        let testURL = try TestData.createTestFolder(path: "create-item")
        let expectedFolderURL = testURL.appending(path: "folder")
        if FileManager.default.fileExists(atPath: expectedFolderURL.path()) {
            try FileManager.default.removeItem(at: expectedFolderURL)
        }

        let itemTemplate = ItemTemplate(
            filename: expectedFolderURL.lastPathComponent,
            contentType: .folder,
            parentItemIdentifier: .rootContainer
                .child(name: testURL.lastPathComponent)
        )
        let fields: NSFileProviderItemFields = [
            .filename, .parentItemIdentifier, .creationDate,
            .contentModificationDate, .fileSystemFlags, .typeAndCreator,
        ]
        let progress = Progress()

        _ = try await ext.createItem(
            basedOn: itemTemplate,
            fields: fields,
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: progress
        )

        #expect(
            FileManager.default.fileExists(atPath: expectedFolderURL.path())
        )
    }

    @Test func deleteItemFolder() async throws {
        let ext = try getExtension()

        let path = "delete-item/folder"
        let folderToDeleteURL = try TestData.createTestFolder(path: path)
        let version = NSFileProviderItemVersion()
        let request = NSFileProviderRequest()
        let progress = Progress()

        try await ext.deleteItem(
            identifier: .rootContainer.child(name: path),
            baseVersion: version,
            request: request,
            progress: progress
        )

        #expect(
            !FileManager.default.fileExists(atPath: folderToDeleteURL.path())
        )
    }
}

final class ItemTemplate: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier =
        NSFileProviderItemIdentifier(UUID().uuidString)
    var parentItemIdentifier: NSFileProviderItemIdentifier
    var filename: String
    var contentType: UTType
    var creationDate: Date?
    var contentModificationDate: Date?
    var fileSystemFlags: NSFileProviderFileSystemFlags

    init(
        filename: String,
        contentType: UTType,
        parentItemIdentifier: NSFileProviderItemIdentifier = .rootContainer,
        creationDate: Date? = nil,
        contentModificationDate: Date? = nil,
        fileSystemFlags: NSFileProviderFileSystemFlags = [
            .userExecutable, .userReadable, .userWritable,
        ]
    ) {
        self.filename = filename
        self.contentType = contentType
        self.parentItemIdentifier = parentItemIdentifier
        self.creationDate = creationDate
        self.contentModificationDate = contentModificationDate
        self.fileSystemFlags = fileSystemFlags
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

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
    ) async throws -> (NSFileProviderItem, NSFileProviderItemFields, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            let operationProgress = self.createItem(
                basedOn: itemTemplate,
                fields: fields,
                contents: url,
                options: options,
                request: request
            ) { item, fields, blah, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: (item, fields, blah))
                }
            }

            progress.addChild(operationProgress, withPendingUnitCount: 1)
        }
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let operationProgress = self.deleteItem(
                identifier: identifier,
                baseVersion: version,
                options: options,
                request: request
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }

            progress.addChild(operationProgress, withPendingUnitCount: 1)
        }
    }
}
