import Common
import Foundation
import Testing

@testable import CoreKit

struct ConnectionConfigModelTests {
    @Test func sshCommandUsesUserAndHost() {
        let model = ConnectionConfigModel(host: "example.com", user: "shad")
        #expect(model.sshCommand == "ssh shad@example.com")
    }

    @Test func sshCommandIncludesNonDefaultPort() {
        let model = ConnectionConfigModel(
            host: "example.com",
            port: 2222,
            user: "shad"
        )
        #expect(model.sshCommand == "ssh -p 2222 shad@example.com")
    }

    @Test func sshCommandOmitsDefaultPort() {
        let model = ConnectionConfigModel(
            host: "example.com",
            port: 22,
            user: "shad"
        )
        #expect(model.sshCommand == "ssh shad@example.com")
    }

    @Test func sshCommandFallsBackToLocalUser() {
        let model = ConnectionConfigModel(host: "example.com")
        #expect(model.sshCommand == "ssh \(NSUserName())@example.com")
    }

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
