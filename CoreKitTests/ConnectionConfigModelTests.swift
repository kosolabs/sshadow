import Common
import Testing

@testable import CoreKit

struct ConnectionConfigModelTests {
    @Test func unsetIgnoreFilenamesUseTheDefault() throws {
        let model = ConnectionConfigModel(host: "example.com")
        let config = try ConnectionConfig(from: model, authMethod: .password("secret"))
        #expect(model.ignoreFilenames == nil)
        #expect(config.ignoreFilenames == [".sshadowignore"])
    }

    @Test func customIgnoreFilenamesCarryOverToConfig() throws {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore", ".sshadowignore"]
        )
        let config = try ConnectionConfig(from: model, authMethod: .password("secret"))
        #expect(config.ignoreFilenames == [".gitignore", ".sshadowignore"])
    }

    @Test func emptyIgnoreFilenamesStayEmpty() throws {
        let model = ConnectionConfigModel(host: "example.com", ignoreFilenames: [])
        let config = try ConnectionConfig(from: model, authMethod: .password("secret"))
        #expect(config.ignoreFilenames == [])
    }

    @Test func duplicateIgnoreFilenamesAreDropped() throws {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore", ".sshadowignore", ".gitignore"]
        )
        let config = try ConnectionConfig(from: model, authMethod: .password("secret"))
        #expect(config.ignoreFilenames == [".gitignore", ".sshadowignore"])
    }

    @Test func customizesIgnoreFilesReflectsWhetherFilenamesAreSet() {
        #expect(!ConnectionConfigModel(host: "example.com").customizesIgnoreFiles)
        #expect(
            ConnectionConfigModel(host: "example.com", ignoreFilenames: [])
                .customizesIgnoreFiles
        )
    }

    @Test func customizingIgnoreFilesStartsFromTheDefault() {
        let model = ConnectionConfigModel(host: "example.com")
        model.customizesIgnoreFiles = true
        #expect(model.ignoreFilenames == [".sshadowignore"])
    }

    @Test func customizingIgnoreFilesKeepsExistingFilenames() {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore"]
        )
        model.customizesIgnoreFiles = true
        #expect(model.ignoreFilenames == [".gitignore"])
    }

    @Test func notCustomizingIgnoreFilesRestoresTheDefault() {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore"]
        )
        model.customizesIgnoreFiles = false
        #expect(model.ignoreFilenames == nil)
        #expect(model.effectiveIgnoreFilenames == [".sshadowignore"])
    }

    @Test(arguments: ["", ".", "..", "dir/.gitignore", "/"])
    func invalidIgnoreFilenamesFailValidation(_ name: String) {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".sshadowignore", name]
        )
        #expect(throws: ConnectionConfig.ValidationError.ignoreFilenameInvalid) {
            try ConnectionConfig(from: model, authMethod: .password("secret"))
        }
    }
}
