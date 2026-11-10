import SwiftData
import Testing

@testable import CoreKit

struct SettingsModelTests {
    @Test func unsetSettingsUseTheDefaults() {
        let settings = SettingsModel()
        #expect(settings.effectiveIgnoreFilenames == [".sshadowignore"])
        #expect(
            settings.effectivePoll
                == PollSettings(
                    interval: .seconds(300),
                    idleThreshold: .seconds(600),
                    watchedInterval: .seconds(10),
                    watchedIdleThreshold: .seconds(120)
                )
        )
        #expect(settings.effectiveConnectTimeout == .seconds(60))
        #expect(settings.effectiveMaxReconnectDelay == .seconds(60))
    }

    @Test func emptyIgnoreFilenamesStayEmpty() {
        let settings = SettingsModel()
        settings.ignoreFilenames = []
        #expect(settings.effectiveIgnoreFilenames == [])
    }

    @Test func manualSyncHasNoPollSettings() {
        let settings = SettingsModel()
        settings.pollsAutomatically = false
        settings.pollIntervalSeconds = 60
        #expect(settings.effectivePoll == nil)
    }

    @Test func settingsCreatesTheRowOnce() throws {
        let context = try ModelContext(
            AppDB.getModelContainer(
                config: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )

        let created = try context.settings()
        created.pollIntervalSeconds = 900
        try context.save()

        #expect(try context.settings() === created)
        #expect(try context.fetchCount(FetchDescriptor<SettingsModel>()) == 1)
    }
}

struct SettingsModelPollFrequencyTests {
    @Test func unsetFrequencyIsTheAutomaticDefault() {
        #expect(SettingsModel().pollFrequency == .automatic(intervalSeconds: nil))
    }

    @Test func choosingAnIntervalStoresIt() {
        let settings = SettingsModel()
        settings.pollFrequency = .automatic(intervalSeconds: 900)
        #expect(settings.pollsAutomatically == nil)
        #expect(settings.effectivePoll?.interval == .seconds(900))
    }

    @Test func choosingManualClearsTheInterval() {
        let settings = SettingsModel()
        settings.pollIntervalSeconds = 900
        settings.pollFrequency = .manual
        #expect(settings.pollsAutomatically == false)
        #expect(settings.pollIntervalSeconds == nil)
        #expect(settings.effectivePoll == nil)
    }

    @Test func leavingManualForTheDefaultClearsBothFields() {
        let settings = SettingsModel()
        settings.pollFrequency = .manual
        settings.pollFrequency = .automatic(intervalSeconds: nil)
        #expect(settings.pollsAutomatically == nil)
        #expect(settings.pollIntervalSeconds == nil)
        #expect(settings.effectivePoll?.interval == .seconds(300))
    }
}

struct SettingsModelValidationTests {
    @Test func defaultIgnoreFilenamesAreValid() throws {
        try SettingsModel().validate()
    }

    @Test(arguments: ["", ".", "..", "dir/.gitignore", "/"])
    func invalidIgnoreFilenamesFailValidation(_ name: String) {
        let settings = SettingsModel()
        settings.ignoreFilenames = [".gitignore", name]
        #expect(throws: ConnectionConfig.ValidationError.ignoreFilenameInvalid) {
            try settings.validate()
        }
    }
}

struct SettingsModelIgnoreFilesTests {
    @Test func unsetIgnoreFilesAreNotCustomized() {
        #expect(!SettingsModel().customizesIgnoreFiles)
    }

    @Test func customizingStartsFromTheBuiltInDefault() {
        let settings = SettingsModel()
        settings.customizesIgnoreFiles = true
        #expect(settings.ignoreFilenames == [".sshadowignore"])
    }

    @Test func customizingKeepsExistingFilenames() {
        let settings = SettingsModel()
        settings.ignoreFilenames = [".gitignore"]
        settings.customizesIgnoreFiles = true
        #expect(settings.ignoreFilenames == [".gitignore"])
    }

    @Test func notCustomizingRestoresTheBuiltInDefault() {
        let settings = SettingsModel()
        settings.ignoreFilenames = [".gitignore"]
        settings.customizesIgnoreFiles = false
        #expect(settings.ignoreFilenames == nil)
        #expect(settings.effectiveIgnoreFilenames == [".sshadowignore"])
    }
}
