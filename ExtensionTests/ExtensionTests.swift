import Common
import FileProvider
import Testing
import UniformTypeIdentifiers

@testable import Extension

private let root = NSFileProviderItemIdentifier.rootContainer

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
        let testFolderPath = "extension-item"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createTestFolder(path: testFolderPath)
        }

        @Test func itemForFileSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/file.txt"
            let contents = "Hello, World!"
            try TestData.createTestFile(path: path, contents: contents)

            let item = try await ext.item(
                for: root.child(name: path),
                request: NSFileProviderRequest(),
                progress: Progress(),
                session: try await ext.manager.getSession(),
            )

            #expect(item.filename == "file.txt")
            #expect(item.contentType == .text)
            #expect(item.documentSize??.intValue == contents.count)
        }

        @Test func itemForFolderSucceeds() async throws {
            let ext = try getExtension()

            let path = "\(testFolderPath)/folder"
            try TestData.createTestFolder(path: path)

            let item = try await ext.item(
                for: root.child(name: path),
                request: NSFileProviderRequest(),
                progress: Progress(),
                session: try await ext.manager.getSession(),
            )

            #expect(item.filename == "folder")
            #expect(item.contentType == .folder)
        }

        @Test func itemForRootSucceeds() async throws {
            let ext = try getExtension()

            let item = try await ext.item(
                for: root,
                request: NSFileProviderRequest(),
                progress: Progress(),
                session: try await ext.manager.getSession(),
            )

            #expect(
                item.filename == "NSFileProviderRootContainerItemIdentifier"
            )
            #expect(item.contentType == .folder)
        }

        @Test func itemForInvalidConfigThrows() async throws {
            let domain = NSFileProviderDomain(
                identifier: NSFileProviderDomainIdentifier(rawValue: "id"),
                displayName: "test"
            )
            let ext = Extension(domain: domain)

            await #expect(throws: NSFileProviderError(.notAuthenticated).self) {
                try await ext.item(
                    for: root,
                    request: NSFileProviderRequest(),
                    progress: Progress(),
                    session: try await ext.manager.getSession(),
                )
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
                    for: root.child(name: "unreachable"),
                    request: NSFileProviderRequest(),
                    progress: Progress(),
                    session: try await ext.manager.getSession(),
                )
            }
        }
    }

    struct FetchContentsTests {
        let testFolderPath = "extension-fetch-contents"
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
                for: root.child(name: path),
                version: nil,
                request: NSFileProviderRequest(),
                progress: progress,
                session: try await ext.manager.getSession(),
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
                for: root.child(name: path),
                version: nil,
                request: NSFileProviderRequest(),
                progress: progress,
                session: try await ext.manager.getSession(),
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
                    for: root.child(name: path),
                    version: nil,
                    request: NSFileProviderRequest(),
                    progress: progress,
                    session: try await ext.manager.getSession(),
                )
            }

            progress.cancel()

            await #expect(throws: CocoaError(.userCancelled).self) {
                try await fetchTask.value
            }
        }
    }

    struct CreateItemTests {
        let testFolderPath = "extension-create-item"
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
                    parentItemIdentifier: root.child(name: testFolderPath),
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
                progress: Progress(),
                session: try await ext.manager.getSession(),
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
                    parentItemIdentifier: root.child(name: testFolderPath),
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
                progress: Progress(),
                session: try await ext.manager.getSession(),
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
                    parentItemIdentifier: root.child(name: testFolderPath),
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
                progress: Progress(),
                session: try await ext.manager.getSession(),
            )

            #expect(
                FileManager.default
                    .fileExists(atPath: expectedFileURL.path())
            )
        }
    }

    @Test func renameFileSucceeds() async throws {
        // mv extension-rename-file/src.txt extension-rename-file/dest.txt
        let startModifyDate = Date(timeIntervalSince1970: 1_750_000_000)
        let endModifyDate = Date(timeIntervalSince1970: 1_760_000_000)

        let folderPath = "extension-rename-file"
        let folderURL = try TestData.createTestFolder(
            path: folderPath,
            modifyDate: startModifyDate
        )
        let folderID = root.child(name: folderPath)

        let srcPath = "\(folderPath)/src.txt"
        let srcURL = try TestData.createTestFile(
            path: srcPath,
            contents: "data",
            modifyDate: startModifyDate
        )
        let srcID = root.child(name: srcPath)

        let destPath = "\(folderPath)/dest.txt"
        let destURL = try TestData.removeTestItem(path: destPath)

        let ext = try getExtension()

        // Modify FPItem(id: FPItemID(extension-rename-file/src.txt), parentId: FPItemID(extension-rename-file), filename: dest.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 2, filename)
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcID,
                parentItemIdentifier: folderID,
                filename: destURL.lastPathComponent,
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.filename],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession(),
        )

        #expect(FileManager.default.fileExists(at: destURL))
        #expect(!FileManager.default.fileExists(at: srcURL))

        // Modify FPItem(id: FPItemID(extension-rename-file), parentId: FPItemID.rootContainer, filename: extension-rename-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 20:18:28 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: folderID,
                parentItemIdentifier: folderID.parent,
                filename: folderID.name,
                contentType: .directory,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                contentModificationDate: endModifyDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession(),
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: folderURL)
        #expect(actualModifyDate == endModifyDate)

        // Item FPItemID(extension-rename-file/src.txt)
        await #expect(throws: NSFileProviderError(.noSuchItem).self) {
            try await ext.item(
                for: srcID,
                request: NSFileProviderRequest(),
                progress: Progress(),
                session: try await ext.manager.getSession()
            )
        }
    }

    @Test func moveFileSucceeds() async throws {
        // mv extension-move-file/src/file.txt extension-move-file/dest/
        let startModifyDate = Date(timeIntervalSince1970: 1_750_000_000)
        let endModifyDate = Date(timeIntervalSince1970: 1_760_000_000)

        let srcFolderPath = "extension-move-file/src"
        let srcFolderURL = try TestData.createTestFolder(
            path: srcFolderPath,
            modifyDate: startModifyDate
        )
        let srcFolderID = root.child(name: srcFolderPath)

        let srcPath = "\(srcFolderPath)/file.txt"
        let srcURL = try TestData.createTestFile(
            path: srcPath,
            contents: "data",
            modifyDate: startModifyDate
        )
        let srcID = root.child(name: srcPath)

        let destFolderPath = "extension-move-file/dest"
        let destFolderURL = try TestData.createTestFolder(
            path: destFolderPath,
            modifyDate: startModifyDate
        )
        let destFolderID = root.child(name: destFolderPath)

        let destPath = "\(destFolderPath)/file.txt"
        let destURL = TestData.getTestURL(path: destPath)

        let ext = try getExtension()

        // Modify FPItem(id: FPItemID(extension-move-file/src/file.txt), parentId: FPItemID(extension-move-file/dest), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 4, parentItemIdentifier)
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcID,
                parentItemIdentifier: destFolderID,
                filename: srcURL.lastPathComponent,
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                isDownloaded: true,
                isMostRecentVersionDownloaded: true
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.parentItemIdentifier],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession(),
        )

        #expect(FileManager.default.fileExists(at: destURL))
        #expect(!FileManager.default.fileExists(at: srcURL))

        // Modify FPItem(id: FPItemID(extension-move-file/dest), parentId: FPItemID(extension-move-file), filename: dest, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: destFolderID,
                parentItemIdentifier: destFolderID.parent,
                filename: destFolderID.name,
                contentType: .directory,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                contentModificationDate: endModifyDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession(),
        )

        let actualDestModifyDate = try FileManager.default.modifyDate(
            of: destFolderURL
        )
        #expect(actualDestModifyDate == endModifyDate)

        // Modify FPItem(id: FPItemID(extension-move-file/src), parentId: FPItemID(extension-move-file), filename: src, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcFolderID,
                parentItemIdentifier: srcFolderID.parent,
                filename: srcFolderID.name,
                contentType: .directory,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                contentModificationDate: endModifyDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession(),
        )

        let actualSrcModifyDate = try FileManager.default.modifyDate(
            of: srcFolderURL
        )
        #expect(actualSrcModifyDate == endModifyDate)

        // Item FPItemID(extension-move-file/src/file.txt)
        await #expect(throws: NSFileProviderError(.noSuchItem).self) {
            try await ext.item(
                for: srcID,
                request: NSFileProviderRequest(),
                progress: Progress(),
                session: try await ext.manager.getSession()
            )
        }
    }

    @Test func editFileSucceeds() async throws {
        // echo "World!" >> extension-edit-file/file.txt
        let oldModifyDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newModifyDate = Date(timeIntervalSince1970: 1_760_000_000)

        let folderPath = "extension-edit-file"
        try TestData.createTestFolder(
            path: folderPath,
            modifyDate: oldModifyDate
        )
        let folderID = root.child(name: folderPath)

        let oldContent = "Hello, "
        let filePath = "\(folderPath)/file.txt"
        let fileURL = try TestData.createTestFile(
            path: filePath,
            contents: oldContent,
            modifyDate: oldModifyDate
        )
        let fileID = root.child(name: filePath)

        let ext = try getExtension()

        // Fetch FPItemID(extension-edit-file/file.txt)
        let (oldURL, oldItem) = try await ext.fetchContents(
            for: fileID,
            version: nil,
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession(),
        )

        #expect(oldItem.filename == "file.txt")
        #expect(oldItem.contentType == .text)
        #expect(try String(contentsOf: oldURL, encoding: .utf8) == oldContent)

        // Modify FPItem(id: FPItemID(extension-edit-file/file.txt), parentId: FPItemID(extension-edit-file), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), size: 14, modifyTime: 2026-03-03 22:20:44 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 129, contents, contentModificationDate)
        let newContent = "Hello, World!\n"
        let newContentURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try newContent.write(
            to: newContentURL,
            atomically: false,
            encoding: .utf8
        )

        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileID,
                parentItemIdentifier: folderID,
                filename: "file.txt",
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                documentSize: NSNumber(value: newContent.count),
                contentModificationDate: newModifyDate,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contents, .contentModificationDate],
            contents: newContentURL,
            options: [],
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession(),
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: fileURL)
        #expect(actualModifyDate == newModifyDate)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == newContent)

        // Fetch FPItemID(extension-edit-file/file.txt)
        let (newURL, newItem) = try await ext.fetchContents(
            for: fileID,
            version: nil,
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession(),
        )

        #expect(newItem.filename == "file.txt")
        #expect(newItem.contentType == .text)
        #expect(try String(contentsOf: newURL, encoding: .utf8) == newContent)
    }

    struct DeleteItemTests {
        let testFolderPath = "extension-delete-item"
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

            try await ext.deleteItem(
                identifier: root.child(name: path),
                baseVersion: NSFileProviderItemVersion(),
                request: NSFileProviderRequest(),
                progress: Progress(),
                session: try await ext.manager.getSession(),
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

            try await ext.deleteItem(
                identifier: root.child(name: path),
                baseVersion: NSFileProviderItemVersion(),
                request: NSFileProviderRequest(),
                progress: Progress(),
                session: try await ext.manager.getSession(),
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

            await #expect(throws: NSFileProviderError(.noSuchItem).self) {
                try await ext.deleteItem(
                    identifier: root.child(name: path),
                    baseVersion: NSFileProviderItemVersion(),
                    request: NSFileProviderRequest(),
                    progress: Progress(),
                    session: try await ext.manager.getSession(),
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
    var typeAndCreator: NSFileProviderTypeAndCreator
    var capabilities: NSFileProviderItemCapabilities
    var fileSystemFlags: NSFileProviderFileSystemFlags
    var documentSize: NSNumber?
    var creationDate: Date?
    var contentModificationDate: Date?
    var lastUsedDate: Date?
    var isDownloaded: Bool
    var isMostRecentVersionDownloaded: Bool

    init(
        itemIdentifier: NSFileProviderItemIdentifier =
            NSFileProviderItemIdentifier(UUID().uuidString),
        parentItemIdentifier: NSFileProviderItemIdentifier = .rootContainer,
        filename: String,
        contentType: UTType,
        typeAndCreator: NSFileProviderTypeAndCreator =
            NSFileProviderTypeAndCreator(),
        capabilities: NSFileProviderItemCapabilities = [],
        fileSystemFlags: NSFileProviderFileSystemFlags = [
            .userExecutable, .userReadable, .userWritable,
        ],
        documentSize: NSNumber? = nil,
        creationDate: Date? = nil,
        contentModificationDate: Date? = nil,
        lastUsedDate: Date? = nil,
        isDownloaded: Bool = false,
        isMostRecentVersionDownloaded: Bool = false,
    ) {
        self.itemIdentifier = itemIdentifier
        self.parentItemIdentifier = parentItemIdentifier
        self.filename = filename
        self.contentType = contentType
        self.typeAndCreator = typeAndCreator
        self.capabilities = capabilities
        self.fileSystemFlags = fileSystemFlags
        self.documentSize = documentSize
        self.creationDate = creationDate
        self.contentModificationDate = contentModificationDate
        self.lastUsedDate = lastUsedDate
        self.isDownloaded = isDownloaded
        self.isMostRecentVersionDownloaded = isMostRecentVersionDownloaded
    }
}
