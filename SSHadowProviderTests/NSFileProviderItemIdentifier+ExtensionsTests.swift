import FileProvider
import Testing

struct NSFileProviderItemIdentifierExtensionsTests {
    
    // MARK: - Parent Tests
    
    @Test func rootContainerParentIsRootContainer() {
        let rootContainer: NSFileProviderItemIdentifier = .rootContainer
        #expect(rootContainer.parent() == .rootContainer)
    }
    
    @Test func topLevelItemParentIsRootContainer() {
        let topLevel = NSFileProviderItemIdentifier("folder")
        #expect(topLevel.parent() == .rootContainer)
    }
    
    @Test func nestedItemParentIsParentFolder() {
        let nested = NSFileProviderItemIdentifier("folder/file")
        #expect(nested.parent() == NSFileProviderItemIdentifier("folder"))
    }
    
    @Test func deeplyNestedItemParentIsImmediateParent() {
        let deeplyNested = NSFileProviderItemIdentifier("a/b/c")
        #expect(deeplyNested.parent() == NSFileProviderItemIdentifier("a/b"))
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

    // MARK: - File Property Tests

    @Test func filePropertyReturnsFilenameForSimpleItem() {
        let simpleFile = NSFileProviderItemIdentifier("file.txt")
        #expect(simpleFile.file == "file.txt")
    }

    @Test func filePropertyReturnsFilenameForNestedItem() {
        let nestedFile = NSFileProviderItemIdentifier("folder/file.txt")
        #expect(nestedFile.file == "file.txt")
    }

    @Test func filePropertyReturnsEmptyStringForEmptyIdentifier() {
        let emptyPathFile = NSFileProviderItemIdentifier("")
        #expect(emptyPathFile.file == "")
    }

    // MARK: - Full Path Tests

    @Test func fullPathForRootContainerReturnsBasePath() {
        let base = "/home/user"
        let rootContainer: NSFileProviderItemIdentifier = .rootContainer
        #expect(rootContainer.fullPath(base: base) == base)
    }

    @Test func fullPathForItemReturnsCombinedPath() {
        let base = "/home/user"
        let item = NSFileProviderItemIdentifier("folder/file.txt")
        let expected = "/home/user/folder/file.txt"
        #expect(item.fullPath(base: base) == expected)
    }
}
