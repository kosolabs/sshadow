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

    @Test func initializeInvalidConfigThrows() async throws {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: "id"),
            displayName: "test"
        )
        let ext = Extension(domain: domain)

        await #expect(throws: NSFileProviderError(.notAuthenticated).self) {
            try await ext.manager.getSession()
        }
    }

    @Test func initializeUnreachableServerThrows() async throws {
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

        await #expect(throws: NSFileProviderError(.serverUnreachable).self) {
            try await ext.manager.getSession()
        }
    }

    @Test func readSmallFileSucceeds() async throws {
        // cat extension-read-file/small-file.txt
        let ext = try getExtension()

        let path = "extension-read-file/small-file.txt"
        let contents = "Hello, World!"
        try TestData.createTestFile(path: path, contents: contents)

        // Fetch FPItemID(extension-read-file/small-file.txt)
        let readProgress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: root.child(name: path),
            version: nil,
            request: NSFileProviderRequest(),
            progress: readProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(item.filename == "small-file.txt")
        #expect(item.contentType == .text)
        #expect(item.documentSize??.intValue == contents.count)
        #expect(try String(contentsOf: url, encoding: .utf8) == contents)
        #expect(readProgress.isFinished)
    }

    @Test func readLargeFileSucceeds() async throws {
        // cat extension-read-file/large-file.dat
        let ext = try getExtension()

        let path = "extension-read-file/large-file.dat"
        let data = Data(count: 10_485_760)
        try TestData.createTestFile(path: path, data: data)

        // Fetch FPItemID(extension-read-file/large-file.dat)
        let readProgress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: root.child(name: path),
            version: nil,
            request: NSFileProviderRequest(),
            progress: readProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(item.filename == "large-file.dat")
        #expect(item.documentSize??.intValue == data.count)
        #expect(try Data(contentsOf: url) == data)
        #expect(readProgress.isFinished)
    }

    @Test func readPartialFileSucceeds() async throws {
        // dd if=extension-read-file/partial-file.dat bs=1m skip=5 count=1
        let ext = try getExtension()

        let path = "extension-read-file/partial-file.dat"
        let data = (0..<256).reduce(into: Data()) { data, i in
            data.append(contentsOf: repeatElement(UInt8(i), count: 1024))
        }
        try TestData.createTestFile(path: path, data: data)

        // Read FPItemID(extension-read-file/partial-file.dat) with range Optional({10240, 10240})
        let requestedRange = NSRange(location: 10 * 1024, length: 10 * 1024)
        let readProgress = Progress()
        let (url, item, returnedRange) = try await ext.fetchPartialContents(
            for: root.child(name: path),
            version: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            minimalRange: requestedRange,
            aligningTo: 16384,
            progress: readProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(item.filename == "partial-file.dat")
        #expect(item.documentSize??.intValue == data.count)
        #expect(returnedRange == NSRange(0..<32768))

        let handle = try FileHandle(forReadingFrom: url)
        try handle.seek(toOffset: UInt64(requestedRange.location))
        let actual = try handle.read(upToCount: requestedRange.length)

        let expected = (10..<20).reduce(into: Data()) { data, i in
            data.append(contentsOf: repeatElement(UInt8(i), count: 1024))
        }

        #expect(actual == expected)
        #expect(readProgress.isFinished)
    }

    @Test func readFileWithCancellation() async throws {
        let ext = try getExtension()

        let path = "extension-read-file/cancellable-file.txt"
        let data = Data(count: 10_485_760)
        try TestData.createTestFile(path: path, data: data)

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

    @Test func createFolderSucceeds() async throws {
        // mkdir extension-create-folder/folder
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-folder"
        let testURL = try TestData.createTestFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let testID = root.child(name: testPath)

        let folderPath = "\(testPath)/folder"
        try TestData.removeTestItem(path: folderPath)
        let folderURL = TestData.getTestURL(path: folderPath)
        let folderID = root.child(name: folderPath)

        let ext = try getExtension()

        // Create FPItem(id: FPItemID(__fp/fs/fileID(17967944)), parentId: FPItemID(extension-create-folder), filename: folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), createTime: 2026-03-04 07:05:26 +0000, modifyTime: 2026-03-04 07:05:26 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1478, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let createFolderProgress = Progress()
        _ = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: folderID.parent,
                filename: folderID.name,
                contentType: .folder,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userExecutable, .userReadable, .userWritable,
                ],
                creationDate: newDate,
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            fields: [
                .filename, .parentItemIdentifier, .creationDate,
                .contentModificationDate, .fileSystemFlags, .typeAndCreator,
            ],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: createFolderProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(FileManager.default.fileExists(at: folderURL))
        #expect(try FileManager.default.modifyDate(of: folderURL) == newDate)
        #expect(try FileManager.default.permissions(of: folderURL) == 0o700)

        // Modify FPItem(id: FPItemID(extension-create-folder), parentId: FPItemID.rootContainer, filename: extension-create-folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 07:05:26 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testID,
                parentItemIdentifier: testID.parent,
                filename: testID.name,
                contentType: .directory,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: updateFolderProgress,
            session: try await ext.manager.getSession(),
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testURL)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createFileSucceeds() async throws {
        // echo "Hello, World!" > extension-create-file/file.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-file"
        let testURL = try TestData.createTestFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let testID = root.child(name: testPath)

        let filePath = "\(testPath)/file.txt"
        try TestData.removeTestItem(path: filePath)
        let fileURL = TestData.getTestURL(path: filePath)
        let fileID = root.child(name: filePath)

        let ext = try getExtension()

        // Create FPItem(id: FPItemID(__fp/fs/docID(10961)), parentId: FPItemID(extension-create-file), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 6, readable, writable), size: 14, createTime: 2026-03-04 21:51:16 +0000, modifyTime: 2026-03-04 21:51:16 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let fileToUploadURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let content = "Hello, World!\n"
        try content.write(
            to: fileToUploadURL,
            atomically: false,
            encoding: .utf8
        )
        let uploadProgress = Progress()
        _ = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: fileID.parent,
                filename: fileID.name,
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable,
                ],
                documentSize: NSNumber(value: content.count),
                creationDate: newDate,
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            fields: [
                .contents, .filename, .parentItemIdentifier, .creationDate,
                .contentModificationDate, .fileSystemFlags, .typeAndCreator,
            ],
            contents: fileToUploadURL,
            options: [],
            request: NSFileProviderRequest(),
            progress: uploadProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(FileManager.default.fileExists(at: fileURL))
        #expect(try FileManager.default.modifyDate(of: fileURL) == newDate)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == content)
        #expect(uploadProgress.isFinished)
        #expect(try FileManager.default.permissions(of: fileURL) == 0o600)

        // Modify FPItem(id: FPItemID(extension-create-file), parentId: FPItemID.rootContainer, filename: extension-create-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 21:51:16 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testID,
                parentItemIdentifier: testID.parent,
                filename: testID.name,
                contentType: .directory,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: updateFolderProgress,
            session: try await ext.manager.getSession(),
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testURL)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createLargeFileSucceeds() async throws {
        // dd if=/dev/zero of=extension-create-large-file/file.txt bs=1m count=10
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-large-file"
        let testURL = try TestData.createTestFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let testID = root.child(name: testPath)

        let filePath = "\(testPath)/file.txt"
        try TestData.removeTestItem(path: filePath)
        let fileURL = TestData.getTestURL(path: filePath)
        let fileID = root.child(name: filePath)

        let ext = try getExtension()

        // Create FPItem(id: FPItemID(__fp/fs/docID(10965)), parentId: FPItemID(extension-create-large-file), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 6, readable, writable), size: 10485760, createTime: 2026-03-04 22:15:29 +0000, modifyTime: 2026-03-04 22:15:29 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let fileToUploadURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let content = Data(count: 10_485_760)
        try content.write(to: fileToUploadURL)
        let uploadProgress = Progress()
        _ = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: fileID.parent,
                filename: fileID.name,
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [.userReadable, .userWritable],
                documentSize: NSNumber(value: content.count),
                creationDate: newDate,
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            fields: [
                .contents, .filename, .parentItemIdentifier, .creationDate,
                .contentModificationDate, .fileSystemFlags, .typeAndCreator,
            ],
            contents: fileToUploadURL,
            options: [],
            request: NSFileProviderRequest(),
            progress: uploadProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(FileManager.default.fileExists(at: fileURL))
        #expect(try FileManager.default.modifyDate(of: fileURL) == newDate)
        #expect(try Data(contentsOf: fileURL) == content)
        #expect(uploadProgress.isFinished)
        #expect(try FileManager.default.permissions(of: fileURL) == 0o600)

        // Modify FPItem(id: FPItemID(extension-create-large-file), parentId: FPItemID.rootContainer, filename: extension-create-large-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 22:15:29 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testID,
                parentItemIdentifier: testID.parent,
                filename: testID.name,
                contentType: .directory,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: updateFolderProgress,
            session: try await ext.manager.getSession(),
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testURL)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func renameFileSucceeds() async throws {
        // mv extension-rename-file/src.txt extension-rename-file/dest.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let folderPath = "extension-rename-file"
        let folderURL = try TestData.createTestFolder(
            path: folderPath,
            modifyDate: oldDate
        )
        let folderID = root.child(name: folderPath)

        let srcPath = "\(folderPath)/src.txt"
        let srcURL = try TestData.createTestFile(
            path: srcPath,
            contents: "data",
            modifyDate: oldDate
        )
        let srcID = root.child(name: srcPath)

        let destPath = "\(folderPath)/dest.txt"
        let destURL = try TestData.removeTestItem(path: destPath)

        let ext = try getExtension()

        // Modify FPItem(id: FPItemID(extension-rename-file/src.txt), parentId: FPItemID(extension-rename-file), filename: dest.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 2, filename)
        let renameProgress = Progress()
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
            progress: renameProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(FileManager.default.fileExists(at: destURL))
        #expect(!FileManager.default.fileExists(at: srcURL))
        #expect(renameProgress.isFinished)

        // Modify FPItem(id: FPItemID(extension-rename-file), parentId: FPItemID.rootContainer, filename: extension-rename-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 20:18:28 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
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
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: updateFolderProgress,
            session: try await ext.manager.getSession(),
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: folderURL)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)

        // Item FPItemID(extension-rename-file/src.txt)
        let getOriginalItemProgress = Progress()
        await #expect(throws: NSFileProviderError(.noSuchItem).self) {
            try await ext.item(
                for: srcID,
                request: NSFileProviderRequest(),
                progress: getOriginalItemProgress,
                session: try await ext.manager.getSession()
            )
        }

        #expect(getOriginalItemProgress.isFinished)
    }

    @Test func moveFileSucceeds() async throws {
        // mv extension-move-file/src/file.txt extension-move-file/dest/
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let srcFolderPath = "extension-move-file/src"
        let srcFolderURL = try TestData.createTestFolder(
            path: srcFolderPath,
            modifyDate: oldDate
        )
        let srcFolderID = root.child(name: srcFolderPath)

        let srcPath = "\(srcFolderPath)/file.txt"
        let srcURL = try TestData.createTestFile(
            path: srcPath,
            contents: "data",
            modifyDate: oldDate
        )
        let srcID = root.child(name: srcPath)

        let destFolderPath = "extension-move-file/dest"
        let destFolderURL = try TestData.createTestFolder(
            path: destFolderPath,
            modifyDate: oldDate
        )
        let destFolderID = root.child(name: destFolderPath)

        let destPath = "\(destFolderPath)/file.txt"
        let destURL = TestData.getTestURL(path: destPath)

        let ext = try getExtension()

        // Modify FPItem(id: FPItemID(extension-move-file/src/file.txt), parentId: FPItemID(extension-move-file/dest), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 4, parentItemIdentifier)
        let moveProgress = Progress()
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
            progress: moveProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(FileManager.default.fileExists(at: destURL))
        #expect(!FileManager.default.fileExists(at: srcURL))
        #expect(moveProgress.isFinished)

        // Modify FPItem(id: FPItemID(extension-move-file/dest), parentId: FPItemID(extension-move-file), filename: dest, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateDestFolderProgress = Progress()
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
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: updateDestFolderProgress,
            session: try await ext.manager.getSession(),
        )

        let actualDestModifyDate = try FileManager.default.modifyDate(
            of: destFolderURL
        )
        #expect(actualDestModifyDate == newDate)
        #expect(updateDestFolderProgress.isFinished)

        // Modify FPItem(id: FPItemID(extension-move-file/src), parentId: FPItemID(extension-move-file), filename: src, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateSrcFolderProgress = Progress()
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
                contentModificationDate: newDate,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contentModificationDate],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: updateSrcFolderProgress,
            session: try await ext.manager.getSession(),
        )

        let actualSrcModifyDate = try FileManager.default.modifyDate(
            of: srcFolderURL
        )
        #expect(actualSrcModifyDate == newDate)
        #expect(updateSrcFolderProgress.isFinished)

        // Item FPItemID(extension-move-file/src/file.txt)
        let getOriginalItemProgress = Progress()
        await #expect(throws: NSFileProviderError(.noSuchItem).self) {
            try await ext.item(
                for: srcID,
                request: NSFileProviderRequest(),
                progress: getOriginalItemProgress,
                session: try await ext.manager.getSession()
            )
        }

        #expect(getOriginalItemProgress.isFinished)
    }

    @Test func editFileSucceeds() async throws {
        // echo "World!" >> extension-edit-file/file.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let folderPath = "extension-edit-file"
        try TestData.createTestFolder(
            path: folderPath,
            modifyDate: oldDate
        )
        let folderID = root.child(name: folderPath)

        let oldContent = "Hello, "
        let filePath = "\(folderPath)/file.txt"
        let fileURL = try TestData.createTestFile(
            path: filePath,
            contents: oldContent,
            modifyDate: oldDate
        )
        let fileID = root.child(name: filePath)

        let ext = try getExtension()

        // Fetch FPItemID(extension-edit-file/file.txt)
        let fetchOldProgress = Progress()
        let (oldURL, oldItem) = try await ext.fetchContents(
            for: fileID,
            version: nil,
            request: NSFileProviderRequest(),
            progress: fetchOldProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(oldItem.filename == "file.txt")
        #expect(oldItem.contentType == .text)
        #expect(try String(contentsOf: oldURL, encoding: .utf8) == oldContent)
        #expect(fetchOldProgress.isFinished)

        // Modify FPItem(id: FPItemID(extension-edit-file/file.txt), parentId: FPItemID(extension-edit-file), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), size: 14, modifyTime: 2026-03-03 22:20:44 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 129, contents, contentModificationDate)
        let newContent = "Hello, World!\n"
        let newContentURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try newContent.write(
            to: newContentURL,
            atomically: false,
            encoding: .utf8
        )

        let modifyProgress = Progress()
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
                contentModificationDate: newDate,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contents, .contentModificationDate],
            contents: newContentURL,
            options: [],
            request: NSFileProviderRequest(),
            progress: modifyProgress,
            session: try await ext.manager.getSession(),
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: fileURL)
        #expect(actualModifyDate == newDate)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == newContent)
        #expect(modifyProgress.isFinished)

        // Fetch FPItemID(extension-edit-file/file.txt)
        let fetchNewProgress = Progress()
        let (newURL, newItem) = try await ext.fetchContents(
            for: fileID,
            version: nil,
            request: NSFileProviderRequest(),
            progress: fetchNewProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(newItem.filename == "file.txt")
        #expect(newItem.contentType == .text)
        #expect(try String(contentsOf: newURL, encoding: .utf8) == newContent)
        #expect(fetchNewProgress.isFinished)
    }

    @Test func setFileReadWriteSucceeds() async throws {
        // chmod 600 extension-permissions/file.txt
        let testPath = "extension-permissions"

        let filePath = "\(testPath)/file.txt"
        let fileURL = try TestData.createTestFile(
            path: filePath,
            contents: "data",
            permissions: 0o000
        )
        let fileID = root.child(name: filePath)

        let ext = try getExtension()

        // Modify FPItem(id: FPItemID(extension-permissions/file.txt), parentId: FPItemID(extension-permissions), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 256, fileSystemFlags)
        let modifyProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileID,
                parentItemIdentifier: fileID.parent,
                filename: fileID.name,
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ]
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.fileSystemFlags],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: modifyProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(try FileManager.default.permissions(of: fileURL) == 0o600)
        #expect(modifyProgress.isFinished)
    }

    @Test func setFolderReadWriteExecuteSucceeds() async throws {
        // chmod 700 extension-permissions/folder
        let testPath = "extension-permissions"

        let folderPath = "\(testPath)/folder"
        let folderURL = try TestData.createTestFolder(
            path: folderPath,
            permissions: 0o000
        )
        let folderID = root.child(name: folderPath)

        let ext = try getExtension()

        // Modify FPItem(id: FPItemID(extension-permissions/folder), parentId: FPItemID(extension-permissions), filename: folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 256, fileSystemFlags)
        let modifyProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: folderID,
                parentItemIdentifier: folderID.parent,
                filename: folderID.name,
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .userExecutable,
                ]
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.fileSystemFlags],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: modifyProgress,
            session: try await ext.manager.getSession(),
        )

        #expect(try FileManager.default.permissions(of: folderURL) == 0o700)
        #expect(modifyProgress.isFinished)
    }

    @Test func deleteFolderSucceeds() async throws {
        // rmdir extension-delete-item/folder
        let testPath = "extension-delete-item"

        let folderPath = "\(testPath)/folder"
        let folderURL = try TestData.createTestFolder(path: folderPath)
        let folderID = root.child(name: folderPath)

        let ext = try getExtension()

        // Delete FPItemID(extension-delete-item/folder)
        let progress = Progress()
        try await ext.deleteItem(
            identifier: folderID,
            baseVersion: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            progress: progress,
            session: try await ext.manager.getSession(),
        )

        #expect(!FileManager.default.fileExists(at: folderURL))
        #expect(progress.isFinished)
    }

    @Test func deleteFileSucceeds() async throws {
        // rm extension-delete-item/file.txt
        let testPath = "extension-delete-item"

        let filePath = "\(testPath)/file.txt"
        let contents = "Hello, World!"
        let fileURL = try TestData.createTestFile(
            path: filePath,
            contents: contents
        )
        let fileID = root.child(name: filePath)

        let ext = try getExtension()

        // Delete FPItemID(extension-delete-item/file.txt)
        let progress = Progress()
        try await ext.deleteItem(
            identifier: fileID,
            baseVersion: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            progress: progress,
            session: try await ext.manager.getSession(),
        )

        #expect(!FileManager.default.fileExists(at: fileURL))
        #expect(progress.isFinished)
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
