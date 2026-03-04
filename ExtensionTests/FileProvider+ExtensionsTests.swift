import FileProvider
import Testing

@testable import Extension

struct ItemIdentifierExtensionsTests {

    // MARK: - Name Property Tests

    @Test func filePropertyReturnsFilenameForSimpleItem() {
        let simpleFile = NSFileProviderItemIdentifier("file.txt")
        #expect(simpleFile.name == "file.txt")
    }

    @Test func filePropertyReturnsFilenameForNestedItem() {
        let nestedFile = NSFileProviderItemIdentifier("folder/file.txt")
        #expect(nestedFile.name == "file.txt")
    }

    @Test func filePropertyReturnsEmptyStringForEmptyIdentifier() {
        let emptyPathFile = NSFileProviderItemIdentifier("")
        #expect(emptyPathFile.name == "")
    }

    // MARK: - Parent Tests

    @Test func rootContainerParentIsRootContainer() {
        let rootContainer: NSFileProviderItemIdentifier = .rootContainer
        #expect(rootContainer.parent == .rootContainer)
    }

    @Test func topLevelItemParentIsRootContainer() {
        let topLevel = NSFileProviderItemIdentifier("folder")
        #expect(topLevel.parent == .rootContainer)
    }

    @Test func nestedItemParentIsParentFolder() {
        let nested = NSFileProviderItemIdentifier("folder/file")
        #expect(nested.parent == NSFileProviderItemIdentifier("folder"))
    }

    @Test func deeplyNestedItemParentIsImmediateParent() {
        let deeplyNested = NSFileProviderItemIdentifier("a/b/c")
        #expect(deeplyNested.parent == NSFileProviderItemIdentifier("a/b"))
    }

    // MARK: - Child Tests

    @Test func childOfRootContainerReturnsTopLevelItem() {
        let root = NSFileProviderItemIdentifier.rootContainer
        let childOfRoot = root.child(name: "folder")
        #expect(childOfRoot == NSFileProviderItemIdentifier("folder"))
    }

    @Test func childOfItemReturnsNestedItem() {
        let parent = NSFileProviderItemIdentifier("folder")
        let child = parent.child(name: "file")
        #expect(child == NSFileProviderItemIdentifier("folder/file"))
    }
}

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
