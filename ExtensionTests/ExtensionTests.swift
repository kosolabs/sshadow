import Common
import FileProvider
import Testing

@testable import Extension

struct ExtensionTests {
    @Test func initializeValidConfigSucceeds() throws {
        let uuid = UUID()
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: uuid.uuidString),
            displayName: "test"
        )
        let userInfo = try TestData.getUserInfo(id: uuid)
        domain.userInfo = try userInfo.toDictionary()
        
        let expectedConfig = try TestData.getConnectionConfig(id: uuid)
        
        let actualConfig = Extension(domain: domain).config
        #expect(actualConfig == expectedConfig)
    }
}
