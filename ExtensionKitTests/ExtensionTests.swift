import Common
import FileProvider
import SwiftData
import Testing
import UniformTypeIdentifiers

@testable import ExtensionKit

private let root = NSFileProviderItemIdentifier.rootContainer

private func getExtensionAndAgent() async throws -> (Extension, AgentClient) {
    let agent = try await TestData.getAgentClient()
    let ext = Extension(agent: agent)
    return (ext, agent)
}

@Suite(.serialized)
struct ExtensionTests {
    // TODO: Add a test for invalid config throws NSFileProviderError(.notAuthenticated)
    // TODO: Add a test for unreachable server throws NSFileProviderError(.serverUnreachable)

    @Test func readSmallFileSucceeds() async throws {
        // cat extension-read-file/small-file.txt
        let path = "extension-read-file/small-file.txt"
        let contents = "Hello, World!"
        try TestData.createFile(path: path, contents: contents)
        let (ext, agent) = try await getExtensionAndAgent()

        // Fetch FPItemID(<id>)
        let readProgress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: agent.child(path: path),
            version: nil,
            request: NSFileProviderRequest(),
            progress: readProgress
        )

        #expect(item.filename == "small-file.txt")
        #expect(item.contentType == .text)
        #expect(item.documentSize??.intValue == contents.count)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(try String(contentsOf: url, encoding: .utf8) == contents)
        #expect(readProgress.isFinished)
    }

    @Test func readLargeFileSucceeds() async throws {
        // cat extension-read-file/large-file.dat
        let path = "extension-read-file/large-file.dat"
        let data = Data(count: 10_485_760)
        try TestData.createFile(path: path, data: data)
        let (ext, agent) = try await getExtensionAndAgent()

        // Fetch FPItemID(<id>)
        let readProgress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: agent.child(path: path),
            version: nil,
            request: NSFileProviderRequest(),
            progress: readProgress
        )

        #expect(item.filename == "large-file.dat")
        #expect(item.documentSize??.intValue == data.count)
        #expect(try Data(contentsOf: url) == data)
        #expect(readProgress.isFinished)
    }

    @Test func readPartialFileSucceeds() async throws {
        // dd if=extension-read-file/partial-file.dat bs=1m skip=5 count=1
        let path = "extension-read-file/partial-file.dat"
        let data = (0..<1024).reduce(into: Data()) { data, i in
            data.append(contentsOf: repeatElement(UInt8(i % 256), count: 1024))
        }
        try TestData.createFile(path: path, data: data)
        let (ext, agent) = try await getExtensionAndAgent()

        // Read FPItemID(<id>) with range Optional({10240, 10240})
        let requestedRange = NSRange(location: 10 * 1024, length: 10 * 1024)
        let readProgress = Progress()
        let (url, item, returnedRange) = try await ext.fetchPartialContents(
            for: agent.child(path: path),
            version: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            minimalRange: requestedRange,
            aligningTo: 16384,
            progress: readProgress
        )

        let chunkSize = 256 * 1024  // FileChunk.size
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
        let path = "extension-read-file/cancellable-file.txt"
        let data = Data(count: 10_485_760)
        try TestData.createFile(path: path, data: data)
        let (ext, agent) = try await getExtensionAndAgent()

        let progress = Progress()
        let fetchTask = Task {
            try await ext.fetchContents(
                for: agent.child(path: path),
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

    @Test func createFolderSucceeds() async throws {
        // mkdir extension-create-folder/folder
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-folder"
        let testUrl = try TestData.createFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let (ext, agent) = try await getExtensionAndAgent()
        let testId = try await agent.child(path: testPath)

        let filename = "folder"
        let folderPath = "\(testPath)/\(filename)"
        try TestData.removeItem(path: folderPath)
        let folderUrl = TestData.getUrl(path: folderPath)

        // Create FPItem(id: FPItemID(<osid>), parentId: FPItemID(<pid>), filename: folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), createTime: 2026-03-04 07:05:26 +0000, modifyTime: 2026-03-04 07:05:26 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1478, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let createFolderProgress = Progress()
        let (item, pendingFields, shouldFetch) = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: testId,
                filename: filename,
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
            progress: createFolderProgress
        )

        #expect(item.filename == filename)
        #expect(item.contentType == .folder)
        #expect(
            item.fileSystemFlags == [
                .userReadable, .userWritable, .userExecutable,
            ]
        )
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(FileManager.default.fileExists(at: folderUrl))
        #expect(try FileManager.default.modifyDate(of: folderUrl) == newDate)
        #expect(try FileManager.default.permissions(of: folderUrl) == 0o700)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-create-folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 07:05:26 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testId,
                parentItemIdentifier: agent.parent(of: testId),
                filename: agent.name(of: testId),
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
            progress: updateFolderProgress
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testUrl)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createFileSucceeds() async throws {
        // echo "Hello, World!" > extension-create-file/file.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-file"
        let testUrl = try TestData.createFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let (ext, agent) = try await getExtensionAndAgent()
        let testId = try await agent.child(path: testPath)

        let filename = "file.txt"
        let filePath = "\(testPath)/\(filename)"
        try TestData.removeItem(path: filePath)
        let fileUrl = TestData.getUrl(path: filePath)

        // Create FPItem(id: FPItemID(<osid>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 6, readable, writable), size: 14, createTime: 2026-03-04 21:51:16 +0000, modifyTime: 2026-03-04 21:51:16 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let fileToUploadUrl = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let content = "Hello, World!\n"
        try content.write(
            to: fileToUploadUrl,
            atomically: false,
            encoding: .utf8
        )
        let uploadProgress = Progress()
        let (item, pendingFields, shouldFetch) = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: testId,
                filename: filename,
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
            contents: fileToUploadUrl,
            options: [],
            request: NSFileProviderRequest(),
            progress: uploadProgress
        )

        #expect(item.filename == filename)
        #expect(item.contentType == .text)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(FileManager.default.fileExists(at: fileUrl))
        #expect(try FileManager.default.modifyDate(of: fileUrl) == newDate)
        #expect(try String(contentsOf: fileUrl, encoding: .utf8) == content)
        #expect(uploadProgress.isFinished)
        #expect(try FileManager.default.permissions(of: fileUrl) == 0o600)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-create-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 21:51:16 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testId,
                parentItemIdentifier: agent.parent(of: testId),
                filename: agent.name(of: testId),
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
            progress: updateFolderProgress
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testUrl)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createLargeFileSucceeds() async throws {
        // dd if=/dev/zero of=extension-create-large-file/file.txt bs=1m count=10
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-create-large-file"
        let testUrl = try TestData.createFolder(
            path: testPath,
            modifyDate: oldDate
        )
        let (ext, agent) = try await getExtensionAndAgent()
        let testId = try await agent.child(path: testPath)

        let filename = "file.txt"
        let filePath = "\(testPath)/\(filename)"
        try TestData.removeItem(path: filePath)
        let fileUrl = TestData.getUrl(path: filePath)

        // Create FPItem(id: FPItemID(<osid>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 6, readable, writable), size: 10485760, createTime: 2026-03-04 22:15:29 +0000, modifyTime: 2026-03-04 22:15:29 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let fileToUploadUrl = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let content = Data(count: 10_485_760)
        try content.write(to: fileToUploadUrl)
        let uploadProgress = Progress()
        let (item, pendingFields, shouldFetch) = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: testId,
                filename: filename,
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
            contents: fileToUploadUrl,
            options: [],
            request: NSFileProviderRequest(),
            progress: uploadProgress
        )

        #expect(item.filename == filename)
        #expect(item.contentType == .text)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(FileManager.default.fileExists(at: fileUrl))
        #expect(try FileManager.default.modifyDate(of: fileUrl) == newDate)
        #expect(try Data(contentsOf: fileUrl) == content)
        #expect(uploadProgress.isFinished)
        #expect(try FileManager.default.permissions(of: fileUrl) == 0o600)

        // Modify FPItem(id: FPItemID(<pid>), parentId: .rootContainer, filename: extension-create-large-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 22:15:29 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: testId,
                parentItemIdentifier: agent.parent(of: testId),
                filename: agent.name(of: testId),
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
            progress: updateFolderProgress
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: testUrl)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createSymlinkSucceeds() async throws {
        // ln -s target.md extension-symlink-file/symlink.md
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let testPath = "extension-symlink-file"
        try TestData.createFolder(path: testPath)
        let target = "target.md"
        try TestData.createFile(path: "\(testPath)/\(target)", contents: "data")

        let filename = "symlink.md"
        let symlinkPath = "\(testPath)/\(filename)"
        try TestData.removeItem(path: symlinkPath)
        let symlinkUrl = TestData.getUrl(path: symlinkPath)

        let (ext, agent) = try await getExtensionAndAgent()
        let testId = try await agent.child(path: testPath)

        // Create FPItem(id: FPItemID(<osid>), parentId: <pid>, filename: symlink.md, contentType: public.symlink, target: target.md, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), size: 9, createTime: 2026-05-15 00:34:12 +0000, modifyTime: 2026-05-15 00:34:12 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let createSymlinkProgress = Progress()
        let (item, pendingFields, shouldFetch) = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: testId,
                filename: filename,
                contentType: .symbolicLink,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userExecutable, .userReadable, .userWritable,
                ],
                documentSize: NSNumber(value: target.count),
                creationDate: newDate,
                contentModificationDate: newDate,
                symlinkTargetPath: target,
                isDownloaded: true,
                isMostRecentVersionDownloaded: true,
            ),
            fields: [
                .contents, .filename, .parentItemIdentifier, .creationDate,
                .contentModificationDate, .fileSystemFlags, .typeAndCreator,
            ],
            contents: nil,
            options: [],
            request: NSFileProviderRequest(),
            progress: createSymlinkProgress
        )

        #expect(item.filename == filename)
        #expect(item.contentType == .symbolicLink)
        #expect(
            item.fileSystemFlags == [
                .userReadable, .userWritable, .userExecutable,
            ]
        )
        //        #expect(item.contentModificationDate == newDate)
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        let actualTarget = try FileManager.default
            .destinationOfSymbolicLink(atPath: symlinkUrl.path())
        #expect(actualTarget == target)
        #expect(createSymlinkProgress.isFinished)
    }

    @Test func renameFileSucceeds() async throws {
        // mv extension-rename-file/src.txt extension-rename-file/dest.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let folderPath = "extension-rename-file"
        let folderUrl = try TestData.createFolder(
            path: folderPath,
            modifyDate: oldDate
        )

        let srcPath = "\(folderPath)/src.txt"
        let srcUrl = try TestData.createFile(
            path: srcPath,
            contents: "data",
            modifyDate: oldDate
        )

        let destFilename = "dest.txt"
        let destPath = "\(folderPath)/\(destFilename)"
        let destUrl = try TestData.removeItem(path: destPath)

        let (ext, agent) = try await getExtensionAndAgent()
        let folderId = try await agent.child(path: folderPath)
        let srcId = try await agent.child(path: srcPath)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: dest.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 2, filename)
        let renameProgress = Progress()
        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcId,
                parentItemIdentifier: folderId,
                filename: destUrl.lastPathComponent,
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
            progress: renameProgress
        )

        let item = try #require(maybeItem)
        #expect(item.filename == destFilename)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(item.contentModificationDate == oldDate)
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(FileManager.default.fileExists(at: destUrl))
        #expect(!FileManager.default.fileExists(at: srcUrl))
        #expect(renameProgress.isFinished)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-rename-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 20:18:28 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: folderId,
                parentItemIdentifier: agent.parent(of: folderId),
                filename: agent.name(of: folderId),
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
            progress: updateFolderProgress
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: folderUrl)
        #expect(actualModifyDate == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func moveFileSucceeds() async throws {
        // mv extension-move-file/src/file.txt extension-move-file/dest/
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let srcFolderPath = "extension-move-file/src"
        let srcFolderUrl = try TestData.createFolder(
            path: srcFolderPath,
            modifyDate: oldDate
        )

        let filename = "file.txt"

        let srcPath = "\(srcFolderPath)/\(filename)"
        let srcUrl = try TestData.createFile(
            path: srcPath,
            contents: "data",
            modifyDate: oldDate
        )

        let destFolderPath = "extension-move-file/dest"
        let destFolderUrl = try TestData.createFolder(
            path: destFolderPath,
            modifyDate: oldDate
        )

        let destPath = "\(destFolderPath)/\(filename)"
        let destUrl = TestData.getUrl(path: destPath)

        let (ext, agent) = try await getExtensionAndAgent()
        let srcFolderId = try await agent.child(path: srcFolderPath)
        let srcId = try await agent.child(path: srcPath)
        let destFolderId = try await agent.child(path: destFolderPath)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID(<npid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 4, parentItemIdentifier)
        let moveProgress = Progress()
        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcId,
                parentItemIdentifier: destFolderId,
                filename: srcUrl.lastPathComponent,
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
            progress: moveProgress
        )

        let item = try #require(maybeItem)
        #expect(item.filename == filename)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(item.contentModificationDate == oldDate)
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(FileManager.default.fileExists(at: destUrl))
        #expect(!FileManager.default.fileExists(at: srcUrl))
        #expect(moveProgress.isFinished)

        // Modify FPItem(id: FPItemID(<npid>), parentId: FPItemID(<ppid>), filename: dest, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateDestFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: destFolderId,
                parentItemIdentifier: agent.parent(of: destFolderId),
                filename: agent.name(of: destFolderId),
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
            progress: updateDestFolderProgress
        )

        let actualDestModifyDate = try FileManager.default.modifyDate(
            of: destFolderUrl
        )
        #expect(actualDestModifyDate == newDate)
        #expect(updateDestFolderProgress.isFinished)

        // Modify FPItem(id: FPItemID(<opid>), parentId: FPItemID(<ppid>), filename: src, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateSrcFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcFolderId,
                parentItemIdentifier: agent.parent(of: srcFolderId),
                filename: agent.name(of: srcFolderId),
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
            progress: updateSrcFolderProgress
        )

        let actualSrcModifyDate = try FileManager.default.modifyDate(
            of: srcFolderUrl
        )
        #expect(actualSrcModifyDate == newDate)
        #expect(updateSrcFolderProgress.isFinished)
    }

    @Test func moveAndRenameFileSucceeds() async throws {
        // mv extension-move-rename/src/old.txt extension-move-rename/dest/new.txt
        let srcFolderPath = "extension-move-rename/src"
        try TestData.createFolder(path: srcFolderPath)

        let srcPath = "\(srcFolderPath)/old.txt"
        try TestData.createFile(path: srcPath, contents: "data")

        let destFolderPath = "extension-move-rename/dest"
        try TestData.createFolder(path: destFolderPath)

        let newName = "new.txt"
        let destUrl = TestData.getUrl(path: "\(destFolderPath)/\(newName)")
        try TestData.removeItem(path: "\(destFolderPath)/\(newName)")

        let (ext, agent) = try await getExtensionAndAgent()
        let srcId = try await agent.child(path: srcPath)
        let destFolderId = try await agent.child(path: destFolderPath)

        let progress = Progress()
        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcId,
                parentItemIdentifier: destFolderId,
                filename: newName,
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
            progress: progress
        )

        let item = try #require(maybeItem)
        #expect(item.filename == newName)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(FileManager.default.fileExists(at: destUrl))
        #expect(
            !FileManager.default.fileExists(
                at: TestData.getUrl(path: srcPath)
            )
        )
        #expect(progress.isFinished)
    }

    @Test func moveFilePreservesIdentifier() async throws {
        // mv extension-move-preserve-id/file.txt extension-move-preserve-id/dest/
        let filename = "file.txt"
        let srcPath = "extension-move-preserve-id/\(filename)"
        try TestData.createFile(path: srcPath, contents: "data")

        let destFolderPath = "extension-move-preserve-id/dest"
        try TestData.createFolder(path: destFolderPath)

        try TestData.removeItem(path: "\(destFolderPath)/\(filename)")

        let (ext, agent) = try await getExtensionAndAgent()
        let srcId = try await agent.child(path: srcPath)
        let destFolderId = try await agent.child(path: destFolderPath)

        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcId,
                parentItemIdentifier: destFolderId,
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
            progress: Progress()
        )

        let item = try #require(maybeItem)
        #expect(item.filename == filename)
        #expect(item.id == srcId)
        #expect(item.parentItemIdentifier == destFolderId)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
    }

    @Test func trashFileSucceeds() async throws {
        // mv extension-trash-file/file.txt .sshadow/trash/file.txt
        let filename = "file.txt"
        let filePath = "extension-trash-file/\(filename)"
        let fileUrl = try TestData.createFile(
            path: filePath,
            contents: "data"
        )

        try TestData.removeItem(path: ".sshadow")
        let trashedUrl = TestData.getUrl(path: ".sshadow/trash/\(filename)")

        let (ext, agent) = try await getExtensionAndAgent()
        let fileId = try await agent.child(path: filePath)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID.trashContainer, filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 4, parentItemIdentifier)
        let trashProgress = Progress()
        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileId,
                parentItemIdentifier: .trashContainer,
                filename: agent.name(of: fileId),
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
            progress: trashProgress
        )

        let item = try #require(maybeItem)
        #expect(item.filename == filename)
        #expect(item.id == fileId)
        #expect(item.parentId == .trashContainer)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(FileManager.default.fileExists(at: trashedUrl))
        #expect(!FileManager.default.fileExists(at: fileUrl))
        #expect(trashProgress.isFinished)
    }

    @Test func editFileSucceeds() async throws {
        // echo "World!" >> extension-edit-file/file.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let folderPath = "extension-edit-file"
        try TestData.createFolder(
            path: folderPath,
            modifyDate: oldDate
        )

        let oldContent = "Hello, "
        let filePath = "\(folderPath)/file.txt"
        let fileUrl = try TestData.createFile(
            path: filePath,
            contents: oldContent,
            modifyDate: oldDate
        )

        let (ext, agent) = try await getExtensionAndAgent()
        let folderId = try await agent.child(path: folderPath)
        let fileId = try await agent.child(path: filePath)

        // Fetch FPItemID(<id>)
        let fetchOldProgress = Progress()
        let (oldUrl, oldItem) = try await ext.fetchContents(
            for: fileId,
            version: nil,
            request: NSFileProviderRequest(),
            progress: fetchOldProgress
        )

        #expect(oldItem.filename == "file.txt")
        #expect(oldItem.contentType == .text)
        #expect(try String(contentsOf: oldUrl, encoding: .utf8) == oldContent)
        #expect(fetchOldProgress.isFinished)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), size: 14, modifyTime: 2026-03-03 22:20:44 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 129, contents, contentModificationDate)
        let newContent = "Hello, World!\n"
        let newContentUrl = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try newContent.write(
            to: newContentUrl,
            atomically: false,
            encoding: .utf8
        )

        let modifyProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileId,
                parentItemIdentifier: folderId,
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
            contents: newContentUrl,
            options: [],
            request: NSFileProviderRequest(),
            progress: modifyProgress
        )

        let actualModifyDate = try FileManager.default.modifyDate(of: fileUrl)
        #expect(actualModifyDate == newDate)
        #expect(try String(contentsOf: fileUrl, encoding: .utf8) == newContent)
        #expect(modifyProgress.isFinished)

        // Fetch FPItemID(<id>)
        let fetchNewProgress = Progress()
        let (newUrl, newItem) = try await ext.fetchContents(
            for: fileId,
            version: nil,
            request: NSFileProviderRequest(),
            progress: fetchNewProgress
        )

        #expect(newItem.filename == "file.txt")
        #expect(newItem.contentType == .text)
        #expect(try String(contentsOf: newUrl, encoding: .utf8) == newContent)
        #expect(fetchNewProgress.isFinished)
    }

    @Test func setFileReadWriteSucceeds() async throws {
        // chmod 600 extension-permissions/file.txt
        let testPath = "extension-permissions"

        let filePath = "\(testPath)/file.txt"
        let fileUrl = try TestData.createFile(
            path: filePath,
            contents: "data",
            permissions: 0o000
        )

        let (ext, agent) = try await getExtensionAndAgent()
        let fileId = try await agent.child(path: filePath)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 256, fileSystemFlags)
        let modifyProgress = Progress()
        let (maybeItem, _, _) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileId,
                parentItemIdentifier: agent.parent(of: fileId),
                filename: agent.name(of: fileId),
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
            progress: modifyProgress
        )

        let item = try #require(maybeItem)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(try FileManager.default.permissions(of: fileUrl) == 0o600)
        #expect(modifyProgress.isFinished)
    }

    @Test func setFolderReadWriteExecuteSucceeds() async throws {
        // chmod 700 extension-permissions/folder
        let testPath = "extension-permissions"

        let folderPath = "\(testPath)/folder"
        let folderUrl = try TestData.createFolder(
            path: folderPath,
            permissions: 0o000
        )

        let (ext, agent) = try await getExtensionAndAgent()
        let folderId = try await agent.child(path: folderPath)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 256, fileSystemFlags)
        let modifyProgress = Progress()
        let (maybeItem, _, _) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: folderId,
                parentItemIdentifier: agent.parent(of: folderId),
                filename: agent.name(of: folderId),
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
            progress: modifyProgress
        )

        let item = try #require(maybeItem)
        #expect(
            item.fileSystemFlags == [
                .userReadable, .userWritable, .userExecutable,
            ]
        )
        #expect(try FileManager.default.permissions(of: folderUrl) == 0o700)
        #expect(modifyProgress.isFinished)
    }

    @Test func deleteFolderSucceeds() async throws {
        // rmdir extension-delete-item/folder
        let testPath = "extension-delete-item"

        let folderPath = "\(testPath)/folder"
        let folderUrl = try TestData.createFolder(path: folderPath)

        let (ext, agent) = try await getExtensionAndAgent()
        let folderId = try await agent.child(path: folderPath)

        // Delete FPItemID(<id>)
        let progress = Progress()
        try await ext.deleteItem(
            identifier: folderId,
            baseVersion: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            progress: progress
        )

        #expect(!FileManager.default.fileExists(at: folderUrl))
        #expect(progress.isFinished)
    }

    @Test func deleteFileSucceeds() async throws {
        // rm extension-delete-item/file.txt
        let testPath = "extension-delete-item"

        let filePath = "\(testPath)/file.txt"
        let contents = "Hello, World!"
        let fileUrl = try TestData.createFile(
            path: filePath,
            contents: contents
        )

        let (ext, agent) = try await getExtensionAndAgent()
        let fileId = try await agent.child(path: filePath)

        // Delete FPItemID(<id>)
        let progress = Progress()
        try await ext.deleteItem(
            identifier: fileId,
            baseVersion: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            progress: progress
        )

        #expect(!FileManager.default.fileExists(at: fileUrl))
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
    var symlinkTargetPath: String?
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
        symlinkTargetPath: String? = nil,
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
        self.symlinkTargetPath = symlinkTargetPath
        self.isDownloaded = isDownloaded
        self.isMostRecentVersionDownloaded = isMostRecentVersionDownloaded
    }
}
