import Common
import FileProvider
import SwiftData
import Testing
import UniformTypeIdentifiers

@testable import ExtensionKit

private let root = NSFileProviderItemIdentifier.rootContainer

private func getExtension(id: UUID = UUID()) async throws -> Extension {
    Extension.agentClientFactory = TestData.getAgentClient
    Session.agentClientFactory = TestData.getAgentClient
    DomainDB.urlFactory = { _ in TestData.domainDbStorePath }
    try await TestData.initAppDB()
    return Extension(domain: TestData.domain)
}

// TODO: Remove this after migration to agent in main app
@Suite(.serialized)
struct ExtensionTests {
    @Test func initializeValidConfigSucceeds() async throws {
        let ext = try await getExtension()
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
                bookmark: TestData.getPrivateKeyUrl().bookmarkData()
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
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        let path = "extension-read-file/small-file.txt"
        let contents = "Hello, World!"
        try TestData.createFile(path: path, contents: contents)

        // Fetch FPItemID(<id>)
        let readProgress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: session.child(path: path),
            version: nil,
            request: NSFileProviderRequest(),
            progress: readProgress,
            session: session,
        )

        #expect(item.filename == "small-file.txt")
        #expect(item.contentType == .text)
        #expect(item.documentSize??.intValue == contents.count)
        #expect(try String(contentsOf: url, encoding: .utf8) == contents)
        #expect(readProgress.isFinished)
    }

    @Test func readLargeFileSucceeds() async throws {
        // cat extension-read-file/large-file.dat
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        let path = "extension-read-file/large-file.dat"
        let data = Data(count: 10_485_760)
        try TestData.createFile(path: path, data: data)

        // Fetch FPItemID(<id>)
        let readProgress = Progress()
        let observation = readProgress.observe(\.completedUnitCount) { p, _ in
            print("\(p)")
        }
        defer { observation.invalidate() }

        let (url, item) = try await ext.fetchContents(
            for: session.child(path: path),
            version: nil,
            request: NSFileProviderRequest(),
            progress: readProgress,
            session: session,
        )

        #expect(item.filename == "large-file.dat")
        #expect(item.documentSize??.intValue == data.count)
        #expect(try Data(contentsOf: url) == data)
        #expect(readProgress.isFinished)
    }

    @Test func readPartialFileSucceeds() async throws {
        // dd if=extension-read-file/partial-file.dat bs=1m skip=5 count=1
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        let path = "extension-read-file/partial-file.dat"
        let data = (0..<1024).reduce(into: Data()) { data, i in
            data.append(contentsOf: repeatElement(UInt8(i % 256), count: 1024))
        }
        try TestData.createFile(path: path, data: data)

        // Read FPItemID(<id>) with range Optional({10240, 10240})
        let requestedRange = NSRange(location: 10 * 1024, length: 10 * 1024)
        let readProgress = Progress()
        let (url, item, returnedRange) = try await ext.fetchPartialContents(
            for: session.child(path: path),
            version: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            minimalRange: requestedRange,
            aligningTo: 16384,
            progress: readProgress,
            session: session,
        )

        let chunkSize = FileChunk.size
        #expect(item.filename == "partial-file.dat")
        #expect(item.documentSize??.intValue == data.count)
        #expect(returnedRange == NSRange(0..<chunkSize))

        let handle = try FileHandle(forReadingFrom: url)
        try handle.seek(toOffset: UInt64(requestedRange.location))
        let actual = try handle.read(upToCount: requestedRange.length)

        let expected = (10..<20).reduce(into: Data()) { data, i in
            data.append(contentsOf: repeatElement(UInt8(i % 256), count: 1024))
        }

        #expect(actual == expected)
        #expect(readProgress.isFinished)
    }

    @Test func readFileWithCancellation() async throws {
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        let path = "extension-read-file/cancellable-file.txt"
        let data = Data(count: 10_485_760)
        try TestData.createFile(path: path, data: data)

        let progress = Progress()
        let fetchTask = Task {
            try await ext.fetchContents(
                for: session.child(path: path),
                version: nil,
                request: NSFileProviderRequest(),
                progress: progress,
                session: session,
            )
        }
        progress.cancel()

        await #expect(throws: CocoaError(.userCancelled).self) {
            try await fetchTask.value
        }
    }

    @Test func createFolderSucceeds() async throws {
        let ext = try await getExtension()
        let agent = ext.agent
        let session = try await ext.manager.getSession()

        // mkdir extension-create-folder/folder
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-folder"
        let testURL = try TestData.createFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let testID = try await session.child(path: testPath)

        let folderPath = "\(testPath)/folder"
        try TestData.removeItem(path: folderPath)
        let folderURL = TestData.getUrl(path: folderPath)
        let folderID = try await session.child(path: folderPath)

        // Create FPItem(id: FPItemID(__fp/fs/fileID(17967944)), parentId: FPItemID(<pid>), filename: folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), createTime: 2026-03-04 07:05:26 +0000, modifyTime: 2026-03-04 07:05:26 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1478, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let createFolderProgress = Progress()
        _ = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: agent.parent(of: folderID),
                filename: session.name(of: folderID),
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
            session: session,
        )

        #expect(FileManager.default.fileExists(at: folderURL))
        #expect(try FileManager.default.modifyDate(of: folderURL) == newDate)
        #expect(try FileManager.default.permissions(of: folderURL) == 0o700)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-create-folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 07:05:26 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testID,
                parentItemIdentifier: agent.parent(of: testID),
                filename: session.name(of: testID),
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
            session: session,
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testURL)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createFileSucceeds() async throws {
        let ext = try await getExtension()
        let agent = ext.agent
        let session = try await ext.manager.getSession()

        // echo "Hello, World!" > extension-create-file/file.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-file"
        let testURL = try TestData.createFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let testID = try await session.child(path: testPath)

        let filePath = "\(testPath)/file.txt"
        try TestData.removeItem(path: filePath)
        let fileURL = TestData.getUrl(path: filePath)
        let fileID = try await session.child(path: filePath)

        // Create FPItem(id: FPItemID(__fp/fs/docID(10961)), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 6, readable, writable), size: 14, createTime: 2026-03-04 21:51:16 +0000, modifyTime: 2026-03-04 21:51:16 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
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
                parentItemIdentifier: agent.parent(of: fileID),
                filename: session.name(of: fileID),
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
            session: session,
        )

        #expect(FileManager.default.fileExists(at: fileURL))
        #expect(try FileManager.default.modifyDate(of: fileURL) == newDate)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == content)
        #expect(uploadProgress.isFinished)
        #expect(try FileManager.default.permissions(of: fileURL) == 0o600)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-create-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 21:51:16 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testID,
                parentItemIdentifier: agent.parent(of: testID),
                filename: session.name(of: testID),
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
            session: session,
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testURL)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createLargeFileSucceeds() async throws {
        let ext = try await getExtension()
        let agent = ext.agent
        let session = try await ext.manager.getSession()

        // dd if=/dev/zero of=extension-create-large-file/file.txt bs=1m count=10
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-large-file"
        let testURL = try TestData.createFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let testID = try await session.child(path: testPath)

        let filePath = "\(testPath)/file.txt"
        try TestData.removeItem(path: filePath)
        let fileURL = TestData.getUrl(path: filePath)
        let fileID = try await session.child(path: filePath)

        // Create FPItem(id: FPItemID(__fp/fs/docID(10965)), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 6, readable, writable), size: 10485760, createTime: 2026-03-04 22:15:29 +0000, modifyTime: 2026-03-04 22:15:29 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let fileToUploadURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let content = Data(count: 10_485_760)
        try content.write(to: fileToUploadURL)
        let uploadProgress = Progress()
        _ = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: agent.parent(of: fileID),
                filename: session.name(of: fileID),
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
            session: session,
        )

        #expect(FileManager.default.fileExists(at: fileURL))
        #expect(try FileManager.default.modifyDate(of: fileURL) == newDate)
        #expect(try Data(contentsOf: fileURL) == content)
        #expect(uploadProgress.isFinished)
        #expect(try FileManager.default.permissions(of: fileURL) == 0o600)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-create-large-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 22:15:29 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testID,
                parentItemIdentifier: agent.parent(of: testID),
                filename: session.name(of: testID),
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
            session: session,
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testURL)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func renameFileSucceeds() async throws {
        let ext = try await getExtension()
        let agent = ext.agent
        let session = try await ext.manager.getSession()

        // mv extension-rename-file/src.txt extension-rename-file/dest.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let folderPath = "extension-rename-file"
        let folderURL = try TestData.createFolder(
            path: folderPath,
            modifyDate: oldDate
        )
        let folderID = try await session.child(path: folderPath)

        let srcPath = "\(folderPath)/src.txt"
        let srcURL = try TestData.createFile(
            path: srcPath,
            contents: "data",
            modifyDate: oldDate
        )
        let srcID = try await session.child(path: srcPath)

        let destPath = "\(folderPath)/dest.txt"
        let destURL = try TestData.removeItem(path: destPath)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: dest.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 2, filename)
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
            session: session,
        )

        #expect(FileManager.default.fileExists(at: destURL))
        #expect(!FileManager.default.fileExists(at: srcURL))
        #expect(renameProgress.isFinished)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-rename-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 20:18:28 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: folderID,
                parentItemIdentifier: agent.parent(of: folderID),
                filename: session.name(of: folderID),
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
            session: session,
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: folderURL)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func moveFileSucceeds() async throws {
        let ext = try await getExtension()
        let agent = ext.agent
        let session = try await ext.manager.getSession()

        // mv extension-move-file/src/file.txt extension-move-file/dest/
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let srcFolderPath = "extension-move-file/src"
        let srcFolderURL = try TestData.createFolder(
            path: srcFolderPath,
            modifyDate: oldDate
        )
        let srcFolderID = try await session.child(path: srcFolderPath)

        let srcPath = "\(srcFolderPath)/file.txt"
        let srcURL = try TestData.createFile(
            path: srcPath,
            contents: "data",
            modifyDate: oldDate
        )
        let srcID = try await session.child(path: srcPath)

        let destFolderPath = "extension-move-file/dest"
        let destFolderURL = try TestData.createFolder(
            path: destFolderPath,
            modifyDate: oldDate
        )
        let destFolderID = try await session.child(path: destFolderPath)

        let destPath = "\(destFolderPath)/file.txt"
        let destURL = TestData.getUrl(path: destPath)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID(<npid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 4, parentItemIdentifier)
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

        // Modify FPItem(id: FPItemID(<npid>), parentId: FPItemID(<ppid>), filename: dest, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateDestFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: destFolderID,
                parentItemIdentifier: agent.parent(of: destFolderID),
                filename: session.name(of: destFolderID),
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
            session: session,
        )

        let actualDestModifyDate = try FileManager.default.modifyDate(
            of: destFolderURL
        )
        #expect(actualDestModifyDate == newDate)
        #expect(updateDestFolderProgress.isFinished)

        // Modify FPItem(id: FPItemID(<opid>), parentId: FPItemID(<ppid>), filename: src, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateSrcFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcFolderID,
                parentItemIdentifier: agent.parent(of: srcFolderID),
                filename: session.name(of: srcFolderID),
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
            session: session,
        )

        let actualSrcModifyDate = try FileManager.default.modifyDate(
            of: srcFolderURL
        )
        #expect(actualSrcModifyDate == newDate)
        #expect(updateSrcFolderProgress.isFinished)
    }

    @Test func moveAndRenameFileSucceeds() async throws {
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        // mv extension-move-rename/src/old.txt extension-move-rename/dest/new.txt
        let srcFolderPath = "extension-move-rename/src"
        try TestData.createFolder(path: srcFolderPath)

        let srcPath = "\(srcFolderPath)/old.txt"
        try TestData.createFile(path: srcPath, contents: "data")
        let srcID = try await session.child(path: srcPath)

        let destFolderPath = "extension-move-rename/dest"
        try TestData.createFolder(path: destFolderPath)
        let destFolderID = try await session.child(path: destFolderPath)

        let destURL = TestData.getUrl(path: "\(destFolderPath)/new.txt")
        try TestData.removeItem(path: "\(destFolderPath)/new.txt")

        let progress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcID,
                parentItemIdentifier: destFolderID,
                filename: "new.txt",
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                isDownloaded: true,
                isMostRecentVersionDownloaded: true
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.filename, .parentItemIdentifier],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: progress,
            session: session,
        )

        #expect(FileManager.default.fileExists(at: destURL))
        #expect(
            !FileManager.default.fileExists(
                at: TestData.getUrl(path: srcPath)
            )
        )
        #expect(progress.isFinished)
    }

    @Test func moveFilePreservesIdentifier() async throws {
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        // mv extension-move-preserve-id/file.txt extension-move-preserve-id/dest/
        let srcPath = "extension-move-preserve-id/file.txt"
        try TestData.createFile(path: srcPath, contents: "data")
        let srcID = try await session.child(path: srcPath)

        let destFolderPath = "extension-move-preserve-id/dest"
        try TestData.createFolder(path: destFolderPath)
        let destFolderID = try await session.child(path: destFolderPath)

        try TestData.removeItem(path: "\(destFolderPath)/file.txt")

        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcID,
                parentItemIdentifier: destFolderID,
                filename: "file.txt",
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
            session: session,
        )

        // Original ID should still resolve to the moved file
        let item = try await ext.item(
            for: srcID,
            request: NSFileProviderRequest(),
            progress: Progress(),
            session: try await ext.manager.getSession()
        )
        #expect(item.filename == "file.txt")
        #expect(item.parentItemIdentifier == destFolderID)
    }

    @Test func trashFileSucceeds() async throws {
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        // mv extension-trash-file/file.txt .Trashes/file.txt
        let filePath = "extension-trash-file/file.txt"
        let fileURL = try TestData.createFile(
            path: filePath,
            contents: "data"
        )
        let fileID = try await session.child(path: filePath)

        try TestData.removeItem(path: ".Trashes")
        let trashedURL = TestData.getUrl(path: ".Trashes/file.txt")

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID.trashContainer, filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 4, parentItemIdentifier)
        let trashProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileID,
                parentItemIdentifier: .trashContainer,
                filename: session.name(of: fileID),
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.parentItemIdentifier],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: trashProgress,
            session: session,
        )

        #expect(FileManager.default.fileExists(at: trashedURL))
        #expect(!FileManager.default.fileExists(at: fileURL))
        #expect(trashProgress.isFinished)
    }

    @Test func editFileSucceeds() async throws {
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        // echo "World!" >> extension-edit-file/file.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let folderPath = "extension-edit-file"
        try TestData.createFolder(
            path: folderPath,
            modifyDate: oldDate
        )
        let folderID = try await session.child(path: folderPath)

        let oldContent = "Hello, "
        let filePath = "\(folderPath)/file.txt"
        let fileURL = try TestData.createFile(
            path: filePath,
            contents: oldContent,
            modifyDate: oldDate
        )
        let fileID = try await session.child(path: filePath)

        // Fetch FPItemID(<id>)
        let fetchOldProgress = Progress()
        let (oldURL, oldItem) = try await ext.fetchContents(
            for: fileID,
            version: nil,
            request: NSFileProviderRequest(),
            progress: fetchOldProgress,
            session: session,
        )

        #expect(oldItem.filename == "file.txt")
        #expect(oldItem.contentType == .text)
        #expect(try String(contentsOf: oldURL, encoding: .utf8) == oldContent)
        #expect(fetchOldProgress.isFinished)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), size: 14, modifyTime: 2026-03-03 22:20:44 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 129, contents, contentModificationDate)
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

        // Fetch FPItemID(<id>)
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
        let ext = try await getExtension()
        let agent = ext.agent
        let session = try await ext.manager.getSession()

        // chmod 600 extension-permissions/file.txt
        let testPath = "extension-permissions"

        let filePath = "\(testPath)/file.txt"
        let fileURL = try TestData.createFile(
            path: filePath,
            contents: "data",
            permissions: 0o000
        )
        let fileID = try await session.child(path: filePath)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 256, fileSystemFlags)
        let modifyProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileID,
                parentItemIdentifier: agent.parent(of: fileID),
                filename: session.name(of: fileID),
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
        let ext = try await getExtension()
        let agent = ext.agent
        let session = try await ext.manager.getSession()

        // chmod 700 extension-permissions/folder
        let testPath = "extension-permissions"

        let folderPath = "\(testPath)/folder"
        let folderURL = try TestData.createFolder(
            path: folderPath,
            permissions: 0o000
        )
        let folderID = try await session.child(path: folderPath)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 256, fileSystemFlags)
        let modifyProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: folderID,
                parentItemIdentifier: agent.parent(of: folderID),
                filename: session.name(of: folderID),
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
            session: session,
        )

        #expect(try FileManager.default.permissions(of: folderURL) == 0o700)
        #expect(modifyProgress.isFinished)
    }

    @Test func deleteFolderSucceeds() async throws {
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        // rmdir extension-delete-item/folder
        let testPath = "extension-delete-item"

        let folderPath = "\(testPath)/folder"
        let folderURL = try TestData.createFolder(path: folderPath)
        let folderID = try await session.child(path: folderPath)

        // Delete FPItemID(<id>)
        let progress = Progress()
        try await ext.deleteItem(
            identifier: folderID,
            baseVersion: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            progress: progress,
            session: session,
        )

        #expect(!FileManager.default.fileExists(at: folderURL))
        #expect(progress.isFinished)
    }

    @Test func deleteFileSucceeds() async throws {
        let ext = try await getExtension()
        let session = try await ext.manager.getSession()

        // rm extension-delete-item/file.txt
        let testPath = "extension-delete-item"

        let filePath = "\(testPath)/file.txt"
        let contents = "Hello, World!"
        let fileURL = try TestData.createFile(
            path: filePath,
            contents: contents
        )
        let fileID = try await session.child(path: filePath)

        // Delete FPItemID(<id>)
        let progress = Progress()
        try await ext.deleteItem(
            identifier: fileID,
            baseVersion: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            progress: progress,
            session: session,
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
