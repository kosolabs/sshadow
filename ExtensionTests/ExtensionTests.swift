import Common
import FileProvider
import Testing
import UniformTypeIdentifiers

@testable import Extension

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

struct ExtensionTests {
    @Test func initializeValidConfigSucceeds() async throws {
        let ext = try getExtension()
        let session = try await ext.manager.getSession()
        let actualConfig = session.config

        let id = actualConfig.id
        let expectedConfig = try TestData.getConnectionConfig(id: id)

        #expect(actualConfig == expectedConfig)
    }

    struct ItemTests {
        let testFolderPath = "item"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createTestFolder(path: testFolderPath)
        }

        @Test func itemForFileSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/file.txt"
            let contents = "Hello, World!"
            try TestData.createTestFile(path: path, contents: contents)

            let item = try await ext.item(for: .rootContainer.child(name: path))

            #expect(item.filename == "file.txt")
            #expect(item.contentType == .text)
            #expect(item.documentSize??.intValue == contents.count)
        }

        @Test func itemForFolderSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/folder"
            try TestData.createTestFolder(path: path)

            let item = try await ext.item(for: .rootContainer.child(name: path))

            #expect(item.filename == "folder")
            #expect(item.contentType == .folder)
        }

        @Test func itemForRootSucceeds() async throws {
            let ext = try getExtension()

            let item = try await ext.item(for: .rootContainer)

            #expect(
                item.filename == "NSFileProviderRootContainerItemIdentifier"
            )
            #expect(item.contentType == .folder)
        }

        @Test func itemForMissingFileThrows() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/missing.txt"

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
                identifier: NSFileProviderDomainIdentifier(
                    rawValue: id.uuidString
                ),
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

            await #expect(throws: NSFileProviderError(.serverUnreachable).self)
            {
                try await ext.item(
                    for: .rootContainer.child(name: "unreachable")
                )
            }
        }
    }

    struct FetchContentsTests {
        let testFolderPath = "fetch-contents"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createTestFolder(path: testFolderPath)
        }

        @Test func fetchSmallFileSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/small-file.txt"
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

        @Test func fetchLargeFileSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/large-file.txt"
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

        @Test func fetchFileWithCancellation() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/cancellable-file.txt"
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

    struct CreateItemTests {
        let testFolderPath = "create-item"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createTestFolder(path: testFolderPath)
        }

        @Test func createFolderSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/folder"
            try TestData.removeTestItem(path: path)
            let expectedFolderURL = TestData.getTestURL(path: path)
            #expect(
                !FileManager.default
                    .fileExists(atPath: expectedFolderURL.path())
            )

            _ = try await ext.createItem(
                basedOn: ItemTemplate(
                    parentItemIdentifier: .rootContainer.child(
                        name: testFolderPath
                    ),
                    filename: expectedFolderURL.lastPathComponent,
                    contentType: .folder,
                ),
                fields: [
                    .filename, .parentItemIdentifier, .creationDate,
                    .contentModificationDate, .fileSystemFlags, .typeAndCreator,
                ],
                contents: nil,
                options: [],
                request: NSFileProviderRequest(),
                progress: Progress()
            )

            #expect(
                FileManager.default
                    .fileExists(atPath: expectedFolderURL.path())
            )
        }

        @Test func createSmallFileSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/small-file.txt"
            try TestData.removeTestItem(path: path)
            let expectedFileURL = TestData.getTestURL(path: path)
            #expect(
                !FileManager.default
                    .fileExists(atPath: expectedFileURL.path())
            )

            let fileToUploadURL = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            let content = "Hello, World!"
            try content.write(
                to: fileToUploadURL,
                atomically: false,
                encoding: .utf8
            )

            _ = try await ext.createItem(
                basedOn: ItemTemplate(
                    parentItemIdentifier: .rootContainer.child(
                        name: testFolderPath
                    ),
                    filename: expectedFileURL.lastPathComponent,
                    contentType: .text,
                    documentSize: NSNumber(value: content.count),
                ),
                fields: [
                    .filename, .parentItemIdentifier, .creationDate,
                    .contentModificationDate, .fileSystemFlags, .typeAndCreator,
                ],
                contents: fileToUploadURL,
                options: [],
                request: NSFileProviderRequest(),
                progress: Progress()
            )

            #expect(
                FileManager.default
                    .fileExists(atPath: expectedFileURL.path())
            )
        }

        @Test func createLargeFileSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/large-file.txt"
            try TestData.removeTestItem(path: path)
            let expectedFileURL = TestData.getTestURL(path: path)
            #expect(
                !FileManager.default
                    .fileExists(atPath: expectedFileURL.path())
            )

            let fileToUploadURL = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            let content = String(repeating: "A", count: 10_000_000)
            try content.write(
                to: fileToUploadURL,
                atomically: false,
                encoding: .utf8
            )

            _ = try await ext.createItem(
                basedOn: ItemTemplate(
                    parentItemIdentifier: .rootContainer.child(
                        name: testFolderPath
                    ),
                    filename: expectedFileURL.lastPathComponent,
                    contentType: .text,
                    documentSize: NSNumber(value: content.count),
                ),
                fields: [
                    .filename, .parentItemIdentifier, .creationDate,
                    .contentModificationDate, .fileSystemFlags, .typeAndCreator,
                ],
                contents: fileToUploadURL,
                options: [],
                request: NSFileProviderRequest(),
                progress: Progress()
            )

            #expect(
                FileManager.default
                    .fileExists(atPath: expectedFileURL.path())
            )
        }
    }

    struct ModifyItemTests {
        let testFolderPath = "modify-item"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createTestFolder(path: testFolderPath)
        }

        @Test func renameFileSucceeds() async throws {
            let ext = try getExtension()

            let sourcePath = "\(testFolderPath)/source-file.txt"
            try TestData.createTestFile(path: sourcePath, contents: "data")

            let destinationPath = "\(testFolderPath)/destination-file.txt"
            try TestData.removeTestItem(path: destinationPath)
            let destinationURL = TestData.getTestURL(path: destinationPath)

            let progress = Progress()
            let (item, _, _) = try await ext.modifyItem(
                ItemTemplate(
                    itemIdentifier: .rootContainer.child(name: sourcePath),
                    parentItemIdentifier: .rootContainer.child(
                        name: testFolderPath
                    ),
                    filename: destinationURL.lastPathComponent,
                    contentType: .text,
                ),
                baseVersion: NSFileProviderItemVersion(),
                changedFields: [.filename],
                contents: nil,
                options: [],
                request: NSFileProviderRequest(),
                progress: progress
            )

            #expect(item?.filename == "destination-file.txt")
            #expect(
                FileManager.default
                    .fileExists(atPath: destinationURL.path())
            )
            #expect(
                !FileManager.default
                    .fileExists(
                        atPath: TestData.getTestURL(path: sourcePath).path()
                    )
            )
        }

        @Test func moveFileSucceeds() async throws {
            let ext = try getExtension()

            let sourceFolderPath = "\(testFolderPath)/source-folder"
            try TestData.createTestFolder(path: sourceFolderPath)
            let sourceFilePath = "\(sourceFolderPath)/file.txt"
            try TestData.createTestFile(path: sourceFilePath, contents: "data")

            let destinationFolderPath = "\(testFolderPath)/destination-folder"
            try TestData.createTestFolder(path: destinationFolderPath)
            let destinationFilePath = "\(destinationFolderPath)/file.txt"
            try TestData.removeTestItem(path: destinationFilePath)

            let progress = Progress()
            let (item, _, _) = try await ext.modifyItem(
                ItemTemplate(
                    itemIdentifier: .rootContainer.child(name: sourceFilePath),
                    parentItemIdentifier: .rootContainer.child(
                        name: destinationFolderPath
                    ),
                    filename: "file.txt",
                    contentType: .text,
                ),
                baseVersion: NSFileProviderItemVersion(),
                changedFields: [.parentItemIdentifier],
                contents: nil,
                options: [],
                request: NSFileProviderRequest(),
                progress: progress
            )

            #expect(item?.filename == "file.txt")
            #expect(
                FileManager.default
                    .fileExists(
                        atPath: TestData.getTestURL(path: destinationFilePath)
                            .path()
                    )
            )
            #expect(
                !FileManager.default
                    .fileExists(
                        atPath: TestData.getTestURL(path: sourceFilePath).path()
                    )
            )
        }

        @Test func editFileSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/edit-file.txt"
            try TestData.createTestFile(path: path, contents: "original")

            let newContent = "updated content"
            let newContentURL = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            try newContent.write(
                to: newContentURL,
                atomically: false,
                encoding: .utf8
            )

            let progress = Progress()
            let (item, remainingFields, _) = try await ext.modifyItem(
                ItemTemplate(
                    itemIdentifier: .rootContainer.child(name: path),
                    parentItemIdentifier: .rootContainer.child(
                        name: testFolderPath
                    ),
                    filename: "edit-file.txt",
                    contentType: .text,
                    documentSize: NSNumber(value: newContent.count),
                ),
                baseVersion: NSFileProviderItemVersion(),
                changedFields: [.contents],
                contents: newContentURL,
                options: [],
                request: NSFileProviderRequest(),
                progress: progress
            )

            #expect(item?.filename == "edit-file.txt")
            #expect(!remainingFields.contains(.contents))

            let actualContent = try String(
                contentsOf: TestData.getTestURL(path: path),
                encoding: .utf8
            )
            #expect(actualContent == newContent)
        }

        @Test func setModifyTimeSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/modify-time-file.txt"
            try TestData.createTestFile(path: path, contents: "data")

            let newModifyTime = Date(timeIntervalSince1970: 1_000_000)

            let progress = Progress()
            _ = try await ext.modifyItem(
                ItemTemplate(
                    itemIdentifier: .rootContainer.child(name: path),
                    parentItemIdentifier: .rootContainer.child(
                        name: testFolderPath
                    ),
                    filename: "modify-time-file.txt",
                    contentType: .text,
                    contentModificationDate: newModifyTime,
                ),
                baseVersion: NSFileProviderItemVersion(),
                changedFields: [.contentModificationDate],
                contents: nil,
                options: [],
                request: NSFileProviderRequest(),
                progress: progress
            )

            let fileURL = TestData.getTestURL(path: path)
            let attrs = try FileManager.default.attributesOfItem(
                atPath: fileURL.path()
            )
            let actualModifyTime = attrs[.modificationDate] as? Date
            #expect(
                actualModifyTime?.timeIntervalSince1970
                    == newModifyTime.timeIntervalSince1970
            )
        }

        @Test func setAccessTimeSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/access-time-file.txt"
            try TestData.createTestFile(path: path, contents: "data")

            let newAccessTime = Date(timeIntervalSince1970: 1_000_000)

            let progress = Progress()
            _ = try await ext.modifyItem(
                ItemTemplate(
                    itemIdentifier: .rootContainer.child(name: path),
                    parentItemIdentifier: .rootContainer.child(
                        name: testFolderPath
                    ),
                    filename: "access-time-file.txt",
                    contentType: .text,
                    lastUsedDate: newAccessTime,
                ),
                baseVersion: NSFileProviderItemVersion(),
                changedFields: [.lastUsedDate],
                contents: nil,
                options: [],
                request: NSFileProviderRequest(),
                progress: progress
            )

            let fileURL = TestData.getTestURL(path: path)
            var st = stat()
            stat(fileURL.path(), &st)
            let actualAccessTime = Date(
                timeIntervalSince1970: TimeInterval(st.st_atimespec.tv_sec)
            )
            #expect(
                actualAccessTime.timeIntervalSince1970
                    == newAccessTime.timeIntervalSince1970
            )
        }

    }

    struct DeleteItemTests {
        let testFolderPath = "delete-item"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createTestFolder(path: testFolderPath)
        }

        @Test func deleteFolderSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/folder"
            let folderToDeleteURL = try TestData.createTestFolder(path: path)
            #expect(
                FileManager.default
                    .fileExists(atPath: folderToDeleteURL.path())
            )

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
                !FileManager.default
                    .fileExists(atPath: folderToDeleteURL.path())
            )
        }

        @Test func deleteFileSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/file.txt"
            let fileToDeleteURL = try TestData.createTestFile(
                path: path,
                contents: "data"
            )
            #expect(
                FileManager.default
                    .fileExists(atPath: fileToDeleteURL.path())
            )

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
                !FileManager.default
                    .fileExists(atPath: fileToDeleteURL.path())
            )
        }

        @Test func deleteMissingItemThrows() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/missing.txt"
            #expect(
                !FileManager.default
                    .fileExists(atPath: TestData.getTestURL(path: path).path())
            )

            let version = NSFileProviderItemVersion()
            let request = NSFileProviderRequest()
            let progress = Progress()

            await #expect(throws: NSFileProviderError(.noSuchItem).self) {
                try await ext.deleteItem(
                    identifier: .rootContainer.child(name: path),
                    baseVersion: version,
                    request: request,
                    progress: progress
                )
            }
        }
    }
}

final class ItemTemplate: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier
    var parentItemIdentifier: NSFileProviderItemIdentifier
    var filename: String
    var contentType: UTType
    var fileSystemFlags: NSFileProviderFileSystemFlags
    var documentSize: NSNumber?
    var creationDate: Date?
    var contentModificationDate: Date?
    var lastUsedDate: Date?

    init(
        itemIdentifier: NSFileProviderItemIdentifier =
            NSFileProviderItemIdentifier(UUID().uuidString),
        parentItemIdentifier: NSFileProviderItemIdentifier = .rootContainer,
        filename: String,
        contentType: UTType,
        fileSystemFlags: NSFileProviderFileSystemFlags = [
            .userExecutable, .userReadable, .userWritable,
        ],
        documentSize: NSNumber? = nil,
        creationDate: Date? = nil,
        contentModificationDate: Date? = nil,
        lastUsedDate: Date? = nil,
    ) {
        self.itemIdentifier = itemIdentifier
        self.parentItemIdentifier = parentItemIdentifier
        self.filename = filename
        self.contentType = contentType
        self.fileSystemFlags = fileSystemFlags
        self.documentSize = documentSize
        self.creationDate = creationDate
        self.contentModificationDate = contentModificationDate
        self.lastUsedDate = lastUsedDate
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

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        progress: Progress,
    ) async throws -> (NSFileProviderItem?, NSFileProviderItemFields, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            let operationProgress = self.modifyItem(
                item,
                baseVersion: version,
                changedFields: changedFields,
                contents: newContents,
                options: options,
                request: request
            ) { item, fields, bool, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (item, fields, bool))
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
