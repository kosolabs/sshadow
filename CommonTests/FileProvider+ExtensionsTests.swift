import FileProvider
import Testing

@testable import Common

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

struct FileSystemFlagsExtensionsTests {
    @Test func readWritePermissionsIs600() {
        let flags = NSFileProviderFileSystemFlags([
            .userReadable, .userWritable,
        ])

        let permissions = flags.permissions
        #expect(permissions == 0o600)
    }

    @Test func readOnlyPermissionsIs400() {
        let flags = NSFileProviderFileSystemFlags([
            .userReadable
        ])

        let permissions = flags.permissions
        #expect(permissions == 0o400)
    }

    @Test func writeOnlyPermissionsIs200() {
        let flags = NSFileProviderFileSystemFlags([
            .userWritable
        ])

        let permissions = flags.permissions
        #expect(permissions == 0o200)
    }

    @Test func executePermissionsIs100() {
        let flags = NSFileProviderFileSystemFlags([
            .userExecutable
        ])

        let permissions = flags.permissions
        #expect(permissions == 0o100)
    }

    @Test func noPermissionsIs000() {
        let flags = NSFileProviderFileSystemFlags([])

        let permissions = flags.permissions
        #expect(permissions == 0o000)
    }
}
