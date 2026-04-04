import Common
import FileProvider
import SwiftLibSSH
import Testing
import UniformTypeIdentifiers

@testable import Extension

private func getSession() async throws -> Session {
    let domain = NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier("test"),
        displayName: TestData.name
    )
    let config = try TestData.getConnectionConfig()
    let ssh = try await SSHClient.connect(config: config)
    let sftp = try await ssh.sftp()
    let db = try TestData.getSSHadowDB()
    return Session(domain: domain, config: config, ssh: ssh, sftp: sftp, db: db)
}

struct SessionTests {
    struct ItemTests {
        let testFolderPath = "session-item"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func itemForFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let item = try await session.item(
                for: .rootContainer.child(name: path)
            )

            #expect(item.filename == "file.txt")
            #expect(item.contentType == .text)
            #expect(item.documentSize?.intValue == contents.utf8.count)
        }

        @Test func itemForFolderSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/folder"
            try TestData.createFolder(path: path)

            let item = try await session.item(
                for: .rootContainer.child(name: path)
            )

            #expect(item.filename == "folder")
            #expect(item.contentType == .folder)
        }

        @Test func itemForRootSucceeds() async throws {
            let session = try await getSession()

            let item = try await session.item(for: .rootContainer)

            #expect(
                item.filename == "NSFileProviderRootContainerItemIdentifier"
            )
            #expect(item.contentType == .folder)
        }

        @Test func itemForMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.item(
                    for: .rootContainer.child(
                        name: "\(testFolderPath)/missing.txt"
                    )
                )
            } throws: { error in isNoSuchItemError(error) }
        }
    }

    struct AttributesTests {
        let testFolderPath = "session-attributes"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func attributesForFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let attrs = try await session.attributes(
                for: .rootContainer.child(name: path)
            )

            #expect(attrs.type == .regular)
            #expect(attrs.size == UInt64(contents.utf8.count))
        }

        @Test func attributesForFolderSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/folder"
            try TestData.createFolder(path: path)

            let attrs = try await session.attributes(
                for: .rootContainer.child(name: path)
            )

            #expect(attrs.type == .directory)
        }

        @Test func attributesForMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.attributes(
                    for: .rootContainer.child(
                        name: "\(testFolderPath)/missing.txt"
                    )
                )
            } throws: { error in isNoSuchItemError(error) }
        }

        @Test func setModifyTimeSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/modify-time.txt"
            try TestData.createFile(path: path, contents: "data")

            let newModifyTime = Date(timeIntervalSince1970: 1_000_000)
            try await session.setAttributes(
                for: .rootContainer.child(name: path),
                modifyTime: newModifyTime
            )

            let fileURL = TestData.getURL(path: path)
            let fileAttrs = try FileManager.default.attributesOfItem(
                atPath: fileURL.path()
            )
            let actualModifyTime = fileAttrs[.modificationDate] as? Date
            #expect(
                actualModifyTime?.timeIntervalSince1970
                    == newModifyTime.timeIntervalSince1970
            )
        }

        @Test func setAccessTimeSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/access-time.txt"
            try TestData.createFile(path: path, contents: "data")

            let newAccessTime = Date(timeIntervalSince1970: 2_000_000)
            try await session.setAttributes(
                for: .rootContainer.child(name: path),
                accessTime: newAccessTime
            )

            let fileURL = TestData.getURL(path: path)
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

        @Test func setAttributesForMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.setAttributes(
                    for: .rootContainer.child(
                        name: "\(testFolderPath)/missing.txt"
                    ),
                    modifyTime: Date()
                )
            } throws: { error in isNoSuchItemError(error) }
        }
    }

    struct CreateDirectoryTests {
        let testFolderPath = "session-create-directory"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func createDirectorySucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/new-directory"
            try TestData.removeItem(path: path)
            let directoryURL = TestData.getURL(path: path)
            #expect(
                !FileManager.default.fileExists(atPath: directoryURL.path())
            )

            try await session.createDirectory(
                for: .rootContainer.child(name: path)
            )

            #expect(
                FileManager.default.fileExists(atPath: directoryURL.path())
            )
        }

        @Test func createExistingDirectoryIfExistsSetSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/existing-directory"
            try TestData.createFolder(path: path)
            let directoryURL = TestData.getURL(path: path)

            try await session.createDirectory(
                for: .rootContainer.child(name: path),
                ifExists: .succeed
            )

            #expect(
                FileManager.default.fileExists(atPath: directoryURL.path())
            )
        }

        @Test func createExistingDirectoryIfExistsNotSetThrows() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/existing-directory"
            try TestData.createFolder(path: path)

            await #expect {
                try await session.createDirectory(
                    for: .rootContainer.child(name: path),
                    ifExists: .fail
                )
            } throws: { error in
                (error as NSError).code
                    == NSFileProviderError.filenameCollision.rawValue
                    && (error as NSError).domain == NSFileProviderErrorDomain
            }
        }
    }

    struct MoveTests {
        let testFolderPath = "session-move"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func moveFileSucceeds() async throws {
            let session = try await getSession()

            let sourcePath = "\(testFolderPath)/source.txt"
            try TestData.createFile(path: sourcePath, contents: "data")

            let destinationPath = "\(testFolderPath)/destination.txt"
            try TestData.removeItem(path: destinationPath)

            try await session.move(
                from: .rootContainer.child(name: sourcePath),
                to: .rootContainer.child(name: destinationPath)
            )

            #expect(
                FileManager.default.fileExists(
                    atPath: TestData.getURL(path: destinationPath).path()
                )
            )
            #expect(
                !FileManager.default.fileExists(
                    atPath: TestData.getURL(path: sourcePath).path()
                )
            )
        }

        @Test func moveMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.move(
                    from: .rootContainer.child(
                        name: "\(testFolderPath)/missing.txt"
                    ),
                    to: .rootContainer.child(
                        name: "\(testFolderPath)/destination.txt"
                    )
                )
            } throws: { error in isNoSuchItemError(error) }
        }

        @Test func moveToMissingParentThrowsNoSuchItem() async throws {
            let session = try await getSession()

            let sourcePath = "\(testFolderPath)/source-missing-parent-fail.txt"
            try TestData.createFile(path: sourcePath, contents: "data")

            let destinationPath =
                "\(testFolderPath)/missing-parent-fail/destination.txt"
            try TestData.removeItem(
                path: "\(testFolderPath)/missing-parent-fail"
            )

            await #expect {
                try await session.move(
                    from: .rootContainer.child(name: sourcePath),
                    to: .rootContainer.child(name: destinationPath),
                    ifParentNotExists: .fail
                )
            } throws: { error in isNoSuchItemError(error) }
        }

        @Test func moveToMissingParentForceCreateSucceeds() async throws {
            let session = try await getSession()

            let sourcePath = "\(testFolderPath)/source-missing-parent.txt"
            try TestData.createFile(path: sourcePath, contents: "data")

            let destinationPath =
                "\(testFolderPath)/missing-parent/destination.txt"
            try TestData.removeItem(
                path: "\(testFolderPath)/missing-parent"
            )

            try await session.move(
                from: .rootContainer.child(name: sourcePath),
                to: .rootContainer.child(name: destinationPath),
                ifParentNotExists: .create
            )

            #expect(
                FileManager.default.fileExists(
                    atPath: TestData.getURL(path: destinationPath).path()
                )
            )
            #expect(
                !FileManager.default.fileExists(
                    atPath: TestData.getURL(path: sourcePath).path()
                )
            )
        }

    }

    struct RemoveFileTests {
        let testFolderPath = "session-remove-file"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func removeFileSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/file.txt"
            let fileURL = try TestData.createFile(
                path: path,
                contents: "data"
            )
            #expect(FileManager.default.fileExists(atPath: fileURL.path()))

            try await session.removeFile(
                for: .rootContainer.child(name: path)
            )

            #expect(!FileManager.default.fileExists(atPath: fileURL.path()))
        }

        @Test func removeMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.removeFile(
                    for: .rootContainer.child(
                        name: "\(testFolderPath)/missing.txt"
                    )
                )
            } throws: { error in isNoSuchItemError(error) }
        }
    }

    struct RemoveDirectoryTests {
        let testFolderPath = "session-remove-directory"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func removeDirectorySucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/folder"
            let folderURL = try TestData.createFolder(path: path)
            #expect(FileManager.default.fileExists(atPath: folderURL.path()))

            try await session.removeDirectory(
                for: .rootContainer.child(name: path)
            )

            #expect(!FileManager.default.fileExists(atPath: folderURL.path()))
        }

        @Test func removeNonEmptyDirectorySucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/non-empty-folder"
            let folderURL = try TestData.createFolder(path: path)
            try TestData.createFile(
                path: "\(path)/file.txt",
                contents: "data"
            )
            try TestData.createFolder(path: "\(path)/subfolder")
            try TestData.createFile(
                path: "\(path)/subfolder/nested.txt",
                contents: "nested"
            )
            #expect(FileManager.default.fileExists(atPath: folderURL.path()))

            try await session.removeDirectory(
                for: .rootContainer.child(name: path)
            )

            #expect(!FileManager.default.fileExists(atPath: folderURL.path()))
        }

        @Test func removeMissingDirectoryThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.removeDirectory(
                    for: .rootContainer.child(
                        name: "\(testFolderPath)/missing"
                    )
                )
            } throws: { error in isNoSuchItemError(error) }
        }
    }

    struct WithFileTests {
        let testFolderPath = "session-with-file"
        let testFolderURL: URL

        init() throws {
            testFolderURL = try TestData.createFolder(path: testFolderPath)
        }

        @Test func withFileReadSucceeds() async throws {
            let session = try await getSession()

            let path = "\(testFolderPath)/read-file.txt"
            let contents = "Hello, World!"
            try TestData.createFile(path: path, contents: contents)

            let data = try await session.withFile(
                for: .rootContainer.child(name: path),
                accessType: .readOnly
            ) { file in
                try await file.read()
            }

            #expect(String(data: data, encoding: .utf8) == contents)
        }

        @Test func withFileMissingFileThrowsNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.withFile(
                    for: .rootContainer.child(
                        name: "\(testFolderPath)/missing.txt"
                    ),
                    accessType: .readOnly
                ) { _ in }
            } throws: { error in isNoSuchItemError(error) }
        }
    }

    struct MapErrorTests {
        @Test func mapErrorPassesThroughSuccess() async throws {
            let session = try await getSession()
            let result = try await session.mapError { "success" }
            #expect(result == "success")
        }

        @Test func mapErrorConvertsNoSuchFileToNoSuchItem() async throws {
            let session = try await getSession()

            await #expect {
                try await session.mapError {
                    throw SSHError.sftpError(.noSuchFile, message: "not found")
                }
            } throws: { error in isNoSuchItemError(error) }
        }

        @Test func mapErrorPassesThroughOtherErrors() async throws {
            let session = try await getSession()

            await #expect(throws: SSHError.self) {
                try await session.mapError {
                    throw SSHError.sftpError(
                        .permissionDenied,
                        message: "denied"
                    )
                }
            }
        }
    }
}

func isNoSuchItemError(_ error: any Error) -> Bool {
    (error as NSError).code == NSFileProviderError.noSuchItem.rawValue
        && (error as NSError).domain == NSFileProviderErrorDomain
}
