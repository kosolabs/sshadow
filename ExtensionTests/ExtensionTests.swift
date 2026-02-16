import Common
import FileProvider
import Testing

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

    @Test func itemSucceeds() async throws {
        let ext = try getExtension()
        
        let path = "test-item-succeeds/item.txt"
        let contents = "Hello, World!"
        try TestData.createTestFile(path: path, contents: contents)

        let progress = Progress()
        let item = try await ext.item(
            for: .rootContainer.child(name: path),
            request: NSFileProviderRequest(),
            progress: progress
        )

        #expect(item.filename == "item.txt")
        #expect(item.documentSize??.intValue == contents.count)
    }
}
