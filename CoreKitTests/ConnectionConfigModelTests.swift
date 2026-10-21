import Common
import Testing

@testable import CoreKit

struct ConnectionConfigModelTests {
    @Test func unsetIgnoreFilenamesUseTheDefault() {
        let model = ConnectionConfigModel(host: "example.com")
        let config = ConnectionConfig(from: model, authMethod: .password("secret"))
        #expect(model.ignoreFilenames == nil)
        #expect(config.ignoreFilenames == [".sshadowignore"])
    }

    @Test func customIgnoreFilenamesCarryOverToConfig() {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore", ".sshadowignore"]
        )
        let config = ConnectionConfig(from: model, authMethod: .password("secret"))
        #expect(config.ignoreFilenames == [".gitignore", ".sshadowignore"])
    }

    @Test func emptyIgnoreFilenamesStayEmpty() {
        let model = ConnectionConfigModel(host: "example.com", ignoreFilenames: [])
        let config = ConnectionConfig(from: model, authMethod: .password("secret"))
        #expect(config.ignoreFilenames == [])
    }
}
