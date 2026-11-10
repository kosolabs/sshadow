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
        model.trustHostKey(unrelatedHostKey)
        let config = try ConnectionConfig(
            from: model,
            settings: SettingsModel(),
            authMethod: .password("secret")
        )
        #expect(model.ignoreFilenames == nil)
        #expect(config.ignoreFilenames == [".sshadowignore"])
    }

    @Test func customIgnoreFilenamesCarryOverToConfig() throws {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore", ".sshadowignore"]
        )
        model.trustHostKey(unrelatedHostKey)
        let config = try ConnectionConfig(
            from: model,
            settings: SettingsModel(),
            authMethod: .password("secret")
        )
        #expect(config.ignoreFilenames == [".gitignore", ".sshadowignore"])
    }

    @Test func emptyIgnoreFilenamesStayEmpty() throws {
        let model = ConnectionConfigModel(host: "example.com", ignoreFilenames: [])
        model.trustHostKey(unrelatedHostKey)
        let config = try ConnectionConfig(
            from: model,
            settings: SettingsModel(),
            authMethod: .password("secret")
        )
        #expect(config.ignoreFilenames == [])
    }

    @Test func duplicateIgnoreFilenamesAreDropped() throws {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore", ".sshadowignore", ".gitignore"]
        )
        model.trustHostKey(unrelatedHostKey)
        let config = try ConnectionConfig(
            from: model,
            settings: SettingsModel(),
            authMethod: .password("secret")
        )
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
        model.setCustomizesIgnoreFiles(true, settings: SettingsModel())
        #expect(model.ignoreFilenames == [".sshadowignore"])
    }

    @Test func customizingIgnoreFilesStartsFromTheGlobalDefault() {
        let settings = SettingsModel()
        settings.ignoreFilenames = [".gitignore"]
        let model = ConnectionConfigModel(host: "example.com")
        model.setCustomizesIgnoreFiles(true, settings: settings)
        #expect(model.ignoreFilenames == [".gitignore"])
    }

    @Test func customizingIgnoreFilesKeepsExistingFilenames() {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore"]
        )
        model.setCustomizesIgnoreFiles(true, settings: SettingsModel())
        #expect(model.ignoreFilenames == [".gitignore"])
    }

    @Test func notCustomizingIgnoreFilesRestoresTheDefault() {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".gitignore"]
        )
        model.setCustomizesIgnoreFiles(false, settings: SettingsModel())
        #expect(model.ignoreFilenames == nil)
        #expect(
            model.effectiveIgnoreFilenames(settings: SettingsModel())
                == [".sshadowignore"]
        )
    }

    @Test func unsetIgnoreFilenamesUseTheGlobalDefault() throws {
        let settings = SettingsModel()
        settings.ignoreFilenames = [".gitignore"]
        let model = ConnectionConfigModel(host: "example.com")
        model.trustHostKey(unrelatedHostKey)
        let config = try ConnectionConfig(
            from: model,
            settings: settings,
            authMethod: .password("secret")
        )
        #expect(config.ignoreFilenames == [".gitignore"])
    }

    @Test func customIgnoreFilenamesOverrideTheGlobalDefault() throws {
        let settings = SettingsModel()
        settings.ignoreFilenames = [".gitignore"]
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".sshadowignore"]
        )
        model.trustHostKey(unrelatedHostKey)
        let config = try ConnectionConfig(
            from: model,
            settings: settings,
            authMethod: .password("secret")
        )
        #expect(config.ignoreFilenames == [".sshadowignore"])
    }

    @Test func invalidGlobalIgnoreFilenamesFailValidation() {
        let settings = SettingsModel()
        settings.ignoreFilenames = ["dir/.gitignore"]
        let model = ConnectionConfigModel(host: "example.com")
        #expect(throws: ConnectionConfig.ValidationError.ignoreFilenameInvalid) {
            try ConnectionConfig(
                from: model,
                settings: settings,
                authMethod: .password("secret")
            )
        }
    }

    @Test func configCarriesTheGlobalSettings() throws {
        let settings = SettingsModel()
        settings.pollIntervalSeconds = 900
        settings.pollIdleThresholdSeconds = 1800
        settings.watchedPollIntervalSeconds = 30
        settings.watchedPollIdleThresholdSeconds = 300
        settings.connectTimeoutSeconds = 15
        settings.maxReconnectDelaySeconds = 300
        let model = ConnectionConfigModel(host: "example.com")
        model.trustHostKey(unrelatedHostKey)
        let config = try ConnectionConfig(
            from: model,
            settings: settings,
            authMethod: .password("secret")
        )
        #expect(
            config.poll
                == PollSettings(
                    interval: .seconds(900),
                    idleThreshold: .seconds(1800),
                    watchedInterval: .seconds(30),
                    watchedIdleThreshold: .seconds(300)
                )
        )
        #expect(config.connectTimeout == .seconds(15))
        #expect(config.maxReconnectDelay == .seconds(300))
    }

    @Test func manualSyncLeavesTheConfigWithoutPolling() throws {
        let settings = SettingsModel()
        settings.pollsAutomatically = false
        let model = ConnectionConfigModel(host: "example.com")
        model.trustHostKey(unrelatedHostKey)
        let config = try ConnectionConfig(
            from: model,
            settings: settings,
            authMethod: .password("secret")
        )
        #expect(config.poll == nil)
    }

    @Test(arguments: ["", ".", "..", "dir/.gitignore", "/"])
    func invalidIgnoreFilenamesFailValidation(_ name: String) {
        let model = ConnectionConfigModel(
            host: "example.com",
            ignoreFilenames: [".sshadowignore", name]
        )
        #expect(throws: ConnectionConfig.ValidationError.ignoreFilenameInvalid) {
            try ConnectionConfig(
                from: model,
                settings: SettingsModel(),
                authMethod: .password("secret")
            )
        }
    }
}
