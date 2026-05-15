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

    @Test func flagsFromMode600IsReadableWritable() {
        let flags = NSFileProviderFileSystemFlags(mode: 0o600)
        #expect(flags == [.userReadable, .userWritable])
    }

    @Test func flagsFromMode400IsReadable() {
        let flags = NSFileProviderFileSystemFlags(mode: 0o400)
        #expect(flags == [.userReadable])
    }

    @Test func flagsFromMode200IsWritable() {
        let flags = NSFileProviderFileSystemFlags(mode: 0o200)
        #expect(flags == [.userWritable])
    }

    @Test func flagsFromMode100IsExecutable() {
        let flags = NSFileProviderFileSystemFlags(mode: 0o100)
        #expect(flags == [.userExecutable])
    }

    @Test func flagsFromMode000IsEmpty() {
        let flags = NSFileProviderFileSystemFlags(mode: 0o000)
        #expect(flags == [])
    }

    @Test func flagsFromMode755IgnoresGroupAndOtherBits() {
        let flags = NSFileProviderFileSystemFlags(mode: 0o755)
        #expect(flags == [.userReadable, .userWritable, .userExecutable])
    }
}
