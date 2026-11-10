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
