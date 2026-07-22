import Common
import FileProvider
import SwiftData
import Testing
import UniformTypeIdentifiers

@testable import ExtensionKit

extension TestSandbox {
    fileprivate func getExtensionAndClient() async throws -> (
        Extension, CoreClient
    ) {
        let client = try await client
        let ext = Extension(client: client)
        return (ext, client)
    }
}

@Suite(.serialized)
struct ExtensionTests {
    @Test(arguments: [
        CoreError.serviceUnreachable,
        CoreError.remotePathNotFound,
        CoreError.unexpectedResponse,
    ])
    func mapsToFileProviderServerUnreachable(error: CoreError) {
        let nsError = error.asNSError as NSError
        #expect(nsError.domain == NSFileProviderErrorDomain)
        #expect(nsError.code == NSFileProviderError.serverUnreachable.rawValue)
    }

    @Test(arguments: [
        CoreError.profileNotFound,
        CoreError.notAuthenticated,
    ])
    func mapsToFileProviderNotAuthenticated(error: CoreError) {
        let nsError = error.asNSError as NSError
        #expect(nsError.domain == NSFileProviderErrorDomain)
        #expect(nsError.code == NSFileProviderError.notAuthenticated.rawValue)
    }

    @Test func readSmallFileSucceeds() async throws {
        // cat small-file.txt
        let sandbox = TestSandbox()
        let contents = "Hello, World!"
        try sandbox.createFile(at: "small-file.txt", contents: contents)
        let (ext, client) = try await sandbox.getExtensionAndClient()

        // Fetch FPItemID(<id>)
        let readProgress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: client.child(name: "small-file.txt"),
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
        // cat large-file.dat
        let sandbox = TestSandbox()
        let data = Data(count: 10_485_760)
        try sandbox.createFile(at: "large-file.dat", data: data)
        let (ext, client) = try await sandbox.getExtensionAndClient()

        // Fetch FPItemID(<id>)
        let readProgress = Progress()
        let (url, item) = try await ext.fetchContents(
            for: client.child(name: "large-file.dat"),
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
        // dd if=partial-file.dat bs=1m skip=5 count=1
        let sandbox = TestSandbox()
        let data = (0..<1024).reduce(into: Data()) { data, i in
            data.append(contentsOf: repeatElement(UInt8(i % 256), count: 1024))
        }
        try sandbox.createFile(at: "partial-file.dat", data: data)
        let (ext, client) = try await sandbox.getExtensionAndClient()

        // Read FPItemID(<id>) with range Optional({10240, 10240})
        let requestedRange = NSRange(location: 10 * 1024, length: 10 * 1024)
        let readProgress = Progress()
        let (url, item, returnedRange) = try await ext.fetchPartialContents(
            for: client.child(name: "partial-file.dat"),
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
        let sandbox = TestSandbox()
        let data = Data(count: 10_485_760)
        try sandbox.createFile(at: "cancellable.dat", data: data)
        let (ext, client) = try await sandbox.getExtensionAndClient()

        let progress = Progress()
        let fetchTask = Task {
            try await ext.fetchContents(
                for: client.child(name: "cancellable.dat"),
                version: nil,
                request: NSFileProviderRequest(),
                progress: progress
            )
        }
        progress.cancel()

        await #expect(throws: CoreError.userCancelled) {
            try await fetchTask.value
        }
    }

    @Test func createFolderSucceeds() async throws {
        // mkdir parent/folder
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "parent", modifyDate: oldDate)
        let (ext, client) = try await sandbox.getExtensionAndClient()

        let parentId = try await client.child(name: "parent")

        // Create FPItem(id: FPItemID(<osid>), parentId: FPItemID(<pid>), filename: folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), createTime: 2026-03-04 07:05:26 +0000, modifyTime: 2026-03-04 07:05:26 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1478, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let createFolderProgress = Progress()
        let (item, pendingFields, shouldFetch) = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: parentId,
                filename: "folder",
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

        #expect(item.filename == "folder")
        #expect(item.contentType == .folder)
        #expect(
            item.fileSystemFlags == [
                .userReadable, .userWritable, .userExecutable,
            ]
        )
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(sandbox.exists(at: "parent/folder"))
        #expect(try sandbox.modifyDate(of: "parent/folder") == newDate)
        #expect(try sandbox.permissions(of: "parent/folder") == 0o700)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-create-folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 07:05:26 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: parentId,
                filename: "parent",
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

        #expect(try sandbox.modifyDate(of: "parent") == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createFileSucceeds() async throws {
        // echo "Hello, World!" > parent/file.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "parent", modifyDate: oldDate)
        let (ext, client) = try await sandbox.getExtensionAndClient()

        let parentId = try await client.child(name: "parent")
        let contents = "Hello, World!"
        let fileToUploadUrl = try sandbox.createFile(
            at: UUID().uuidString,
            relativeTo: .shared,
            contents: contents
        )

        // Create FPItem(id: FPItemID(<osid>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 6, readable, writable), size: 14, createTime: 2026-03-04 21:51:16 +0000, modifyTime: 2026-03-04 21:51:16 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let uploadProgress = Progress()
        let (item, pendingFields, shouldFetch) = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: parentId,
                filename: "file.txt",
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable,
                ],
                documentSize: NSNumber(value: contents.count),
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

        #expect(item.filename == "file.txt")
        #expect(item.contentType == .text)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(sandbox.exists(at: "parent/file.txt"))
        #expect(try sandbox.modifyDate(of: "parent/file.txt") == newDate)
        #expect(try sandbox.contents(of: "parent/file.txt") == contents)
        #expect(uploadProgress.isFinished)
        #expect(try sandbox.permissions(of: "parent/file.txt") == 0o600)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: extension-create-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 21:51:16 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: parentId,
                filename: "parent",
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

        #expect(try sandbox.modifyDate(of: "parent") == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createLargeFileSucceeds() async throws {
        // dd if=/dev/zero of=parent/file.dat bs=1m count=10
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "parent", modifyDate: oldDate)
        let (ext, client) = try await sandbox.getExtensionAndClient()

        let parentId = try await client.child(name: "parent")
        let data = Data(count: 10_485_760)
        let fileToUploadUrl = try sandbox.createFile(
            at: UUID().uuidString,
            relativeTo: .shared,
            data: data
        )

        // Create FPItem(id: FPItemID(<osid>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 6, readable, writable), size: 10485760, createTime: 2026-03-04 22:15:29 +0000, modifyTime: 2026-03-04 22:15:29 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let uploadProgress = Progress()
        let (item, pendingFields, shouldFetch) = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: parentId,
                filename: "file.dat",
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [.userReadable, .userWritable],
                documentSize: NSNumber(value: data.count),
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

        #expect(item.filename == "file.dat")
        #expect(item.contentType == .text)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(sandbox.exists(at: "parent/file.dat"))
        #expect(try sandbox.modifyDate(of: "parent/file.dat") == newDate)
        #expect(try sandbox.data(at: "parent/file.dat") == data)
        #expect(uploadProgress.isFinished)
        #expect(try sandbox.permissions(of: "parent/file.dat") == 0o600)

        // Modify FPItem(id: FPItemID(<pid>), parentId: .rootContainer, filename: extension-create-large-file, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-04 22:15:29 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: parentId,
                filename: "parent",
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

        #expect(try sandbox.modifyDate(of: "parent") == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func createSymlinkSucceeds() async throws {
        // ln -s target.md parent/symlink.md
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "parent", modifyDate: oldDate)
        let contents = "Hello, World!"
        try sandbox.createFile(at: "parent/target.txt", contents: contents)
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let parentId = try await client.child(name: "parent")

        // Create FPItem(id: FPItemID(<osid>), parentId: <pid>, filename: symlink.md, contentType: public.symlink, target: target.md, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), size: 9, createTime: 2026-05-15 00:34:12 +0000, modifyTime: 2026-05-15 00:34:12 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 1479, contents, filename, parentItemIdentifier, creationDate, contentModificationDate, fileSystemFlags, typeAndCreator)
        let createSymlinkProgress = Progress()
        let (item, pendingFields, shouldFetch) = try await ext.createItem(
            basedOn: ItemTemplate(
                parentItemIdentifier: parentId,
                filename: "symlink.txt",
                contentType: .symbolicLink,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userExecutable, .userReadable, .userWritable,
                ],
                documentSize: NSNumber(value: contents.count),
                creationDate: newDate,
                contentModificationDate: newDate,
                symlinkTargetPath: "target.txt",
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

        #expect(item.filename == "symlink.txt")
        #expect(item.contentType == .symbolicLink)
        #expect(
            item.fileSystemFlags == [
                .userReadable, .userWritable, .userExecutable,
            ]
        )
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(try sandbox.target(of: "parent/symlink.txt") == "target.txt")
        #expect(createSymlinkProgress.isFinished)
    }

    @Test func renameFileSucceeds() async throws {
        // mv parent/src.txt parent/dest.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "parent", modifyDate: oldDate)
        try sandbox.createFile(
            at: "parent/src.txt",
            contents: "data",
            modifyDate: oldDate
        )
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let parentId = try await client.child(name: "parent")
        let srcId = try await client.child(of: parentId, name: "src.txt")

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: dest.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 2, filename)
        let renameProgress = Progress()
        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcId,
                parentItemIdentifier: parentId,
                filename: "dest.txt",
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
        #expect(item.filename == "dest.txt")
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(item.contentModificationDate == oldDate)
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(sandbox.exists(at: "parent/dest.txt"))
        #expect(!sandbox.exists(at: "parent/src.txt"))
        #expect(renameProgress.isFinished)

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID.rootContainer, filename: parent, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 20:18:28 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: parentId,
                filename: "parent",
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

        #expect(try sandbox.modifyDate(of: "parent") == newDate)
        #expect(updateFolderProgress.isFinished)
    }

    @Test func moveFileSucceeds() async throws {
        // mv src/file.txt dest/
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "src", modifyDate: oldDate)
        try sandbox.createFile(
            at: "src/file.txt",
            contents: "data",
            modifyDate: oldDate
        )
        try sandbox.createFolder(at: "dest", modifyDate: oldDate)
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let srcId = try await client.child(name: "src")
        let fileId = try await client.child(of: srcId, name: "file.txt")
        let destId = try await client.child(name: "dest")

        // Modify FPItem(id: FPItemID(<pid>), parentId: FPItemID(<npid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 4, parentItemIdentifier)
        let moveProgress = Progress()
        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileId,
                parentItemIdentifier: destId,
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
            progress: moveProgress
        )

        let item = try #require(maybeItem)
        #expect(item.filename == "file.txt")
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(item.contentModificationDate == oldDate)
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(sandbox.exists(at: "dest/file.txt"))
        #expect(!sandbox.exists(at: "src/file.txt"))
        #expect(moveProgress.isFinished)

        // Modify FPItem(id: FPItemID(<npid>), parentId: FPItemID(<ppid>), filename: dest, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateDestFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: destId,
                filename: "dest",
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

        #expect(try sandbox.modifyDate(of: "dest") == newDate)
        #expect(updateDestFolderProgress.isFinished)

        // Modify FPItem(id: FPItemID(<opid>), parentId: FPItemID(<ppid>), filename: src, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), modifyTime: 2026-03-03 21:30:15 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 128, contentModificationDate)
        let updateSrcFolderProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: srcId,
                filename: "src",
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

        #expect(try sandbox.modifyDate(of: "src") == newDate)
        #expect(updateSrcFolderProgress.isFinished)
    }

    @Test func moveAndRenameFileSucceeds() async throws {
        // mv src/old.txt dest/new.txt
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "src/old.txt", contents: "data")
        try sandbox.createFolder(at: "dest")
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let srcId = try await client.child(name: "src")
        let fileId = try await client.child(of: srcId, name: "old.txt")
        let destId = try await client.child(name: "dest")

        let progress = Progress()
        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileId,
                parentItemIdentifier: destId,
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
            progress: progress
        )

        let item = try #require(maybeItem)
        #expect(item.filename == "new.txt")
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(sandbox.exists(at: "dest/new.txt"))
        #expect(!sandbox.exists(at: "src/old.txt"))
        #expect(progress.isFinished)
    }

    @Test func moveFilePreservesIdentifier() async throws {
        // mv file.txt dest/
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file.txt", contents: "data")
        try sandbox.createFolder(at: "dest")
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let srcId = try await client.child(name: "file.txt")
        let destFolderId = try await client.child(name: "dest")

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
        #expect(item.filename == "file.txt")
        #expect(item.id == srcId)
        #expect(item.parentItemIdentifier == destFolderId)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
    }

    @Test func trashFileSucceeds() async throws {
        // mv file.txt .sshadow/trash/file.txt
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file.txt", contents: "data")
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let fileId = try await client.child(name: "file.txt")

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID.trashContainer, filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 4, parentItemIdentifier)
        let trashProgress = Progress()
        let (maybeItem, pendingFields, shouldFetch) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileId,
                parentItemIdentifier: .trashContainer,
                filename: "file.txt",
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
        #expect(item.filename == "file.txt")
        #expect(item.id == fileId)
        #expect(item.parentId == .trashContainer)
        #expect(item.fileSystemFlags == [.userReadable, .userWritable])
        #expect(pendingFields.isEmpty)
        #expect(!shouldFetch)
        #expect(sandbox.exists(at: ".sshadow/trash/file.txt"))
        #expect(!sandbox.exists(at: "file.txt"))
        #expect(trashProgress.isFinished)
    }

    @Test func editFileSucceeds() async throws {
        // echo "World!" >> parent/file.txt
        let oldDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "parent", modifyDate: oldDate)
        let oldContents = "Hello, "
        try sandbox.createFile(
            at: "parent/file.txt",
            contents: oldContents,
            modifyDate: oldDate
        )
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let parentId = try await client.child(name: "parent")
        let fileId = try await client.child(of: parentId, name: "file.txt")

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
        #expect(try String(contentsOf: oldUrl, encoding: .utf8) == oldContents)
        #expect(fetchOldProgress.isFinished)

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), size: 14, modifyTime: 2026-03-03 22:20:44 +0000, downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 129, contents, contentModificationDate)
        let newContents = "Hello, World!\n"
        let newContentsUrl = try sandbox.createFile(
            at: UUID().uuidString,
            relativeTo: .shared,
            contents: newContents
        )

        let modifyProgress = Progress()
        _ = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileId,
                parentItemIdentifier: parentId,
                filename: "file.txt",
                contentType: .text,
                capabilities: [.allowsReading, .allowsWriting],
                fileSystemFlags: [
                    .userReadable, .userWritable, .pathExtensionHidden,
                ],
                documentSize: NSNumber(value: newContents.count),
                contentModificationDate: newDate,
            ),
            baseVersion: NSFileProviderItemVersion(),
            changedFields: [.contents, .contentModificationDate],
            contents: newContentsUrl,
            options: [],
            request: NSFileProviderRequest(),
            progress: modifyProgress
        )

        #expect(try sandbox.modifyDate(of: "parent/file.txt") == newDate)
        #expect(try sandbox.contents(of: "parent/file.txt") == newContents)
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
        #expect(try String(contentsOf: newUrl, encoding: .utf8) == newContents)
        #expect(fetchNewProgress.isFinished)
    }

    @Test func setFileReadWriteSucceeds() async throws {
        // chmod 600 file.txt
        let sandbox = TestSandbox()
        try sandbox.createFile(
            at: "file.txt",
            contents: "data",
            permissions: 0o000
        )
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let fileId = try await client.child(name: "file.txt")

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: file.txt, contentType: public.plain-text, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 22, readable, writable, pathExtensionHidden), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 256, fileSystemFlags)
        let modifyProgress = Progress()
        let (maybeItem, _, _) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: fileId,
                filename: "file.txt",
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
        #expect(try sandbox.permissions(of: "file.txt") == 0o600)
        #expect(modifyProgress.isFinished)
    }

    @Test func setFolderReadWriteExecuteSucceeds() async throws {
        // chmod 700 folder
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "folder", permissions: 0o000)
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let folderId = try await client.child(name: "folder")

        // Modify FPItem(id: FPItemID(<id>), parentId: FPItemID(<pid>), filename: folder, contentType: public.folder, capabilities: FPItemCapabilities(rawValue: 3, reading, writing), fileSystemFlags: FPFileSystemFlags(rawValue: 7, executable, readable, writable), downloaded, mostRecentVersionDownloaded) for FPItemFields(rawValue: 256, fileSystemFlags)
        let modifyProgress = Progress()
        let (maybeItem, _, _) = try await ext.modifyItem(
            ItemTemplate(
                itemIdentifier: folderId,
                filename: "folder",
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
        #expect(try sandbox.permissions(of: "folder") == 0o700)
        #expect(modifyProgress.isFinished)
    }

    @Test func deleteFolderSucceeds() async throws {
        // rmdir folder
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: "folder")
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let folderId = try await client.child(name: "folder")

        // Delete FPItemID(<id>)
        let progress = Progress()
        try await ext.deleteItem(
            identifier: folderId,
            baseVersion: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            progress: progress
        )

        #expect(!sandbox.exists(at: "folder"))
        #expect(progress.isFinished)
    }

    @Test func deleteFileSucceeds() async throws {
        // rm file.txt
        let sandbox = TestSandbox()
        try sandbox.createFile(at: "file.txt", contents: "Hello, World!")
        let (ext, client) = try await sandbox.getExtensionAndClient()
        let fileId = try await client.child(name: "file.txt")

        // Delete FPItemID(<id>)
        let progress = Progress()
        try await ext.deleteItem(
            identifier: fileId,
            baseVersion: NSFileProviderItemVersion(),
            request: NSFileProviderRequest(),
            progress: progress
        )

        #expect(!sandbox.exists(at: "file.txt"))
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
