import FileProvider
import Testing

@testable import ExtensionKit

struct ItemFieldsExtensionsTests {
    @Test func descIncludesAllFields() {
        let fields: NSFileProviderItemFields = [
            .contents, .filename, .lastUsedDate,
        ]

        let desc = fields.desc

        #expect(desc.contains("contents"))
        #expect(desc.contains("filename"))
        #expect(desc.contains("lastUsedDate"))
    }

    @Test func descIsEmptyWhenNoFields() {
        let fields: NSFileProviderItemFields = []

        let desc = fields.desc

        #expect(desc == "FPItemFields(rawValue: 0)")
    }
}

struct SyncAnchorExtensionTests {
    @Test func zeroSucceeds() {
        let anchor = NSFileProviderSyncAnchor(0)
        #expect(anchor.value == 0)
    }

    @Test func positiveIntegerSucceeds() {
        let anchor = NSFileProviderSyncAnchor(1024)
        #expect(anchor.value == 1024)
    }

    @Test func largeIntegerSucceeds() {
        let anchor = NSFileProviderSyncAnchor(UInt64.max)
        #expect(anchor.value == UInt64.max)
    }
}
