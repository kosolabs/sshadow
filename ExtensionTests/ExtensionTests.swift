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
        
        let path = "item-file/item.txt"
        let contents = "Hello, World!"
        try TestData.createTestFile(path: path, contents: contents)
        
        let progress = Progress()
        let item = try await ext.item(
            for: .rootContainer.child(name: path),
            request: NSFileProviderRequest(),
            progress: progress
        )
        
        #expect(item.filename == "item.txt")
        #expect(item.contentType == .text)
        #expect(item.documentSize??.intValue == contents.count)
    }
    
    @Test func itemForFolderSucceeds() async throws {
        let ext = try getExtension()
        
        let path = "item-folder"
        try TestData.createTestFolder(path: path)
        
        let progress = Progress()
        let item = try await ext.item(
            for: .rootContainer.child(name: path),
            request: NSFileProviderRequest(),
            progress: progress
        )
        
        #expect(item.filename == "item-folder")
        #expect(item.contentType == .folder)
    }
    
    @Test func itemForRootSucceeds() async throws {
        let ext = try getExtension()
        
        let progress = Progress()
        let item = try await ext.item(
            for: .rootContainer,
            request: NSFileProviderRequest(),
            progress: progress
        )
        
        #expect(item.filename == "NSFileProviderRootContainerItemIdentifier")
        #expect(item.contentType == .folder)
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
