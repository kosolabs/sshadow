import Common
import FileProvider
import Testing
import UniformTypeIdentifiers

@testable import ExtensionKit

private func makeItem(
    id: String = "id",
    parentId: String? = "parent",
    name: String = "file.txt",
    kind: Item.Kind = .file,
    size: UInt64? = 1024,
    flags: Item.Flags? = .rw,
    accessTime: Date? = Date(timeIntervalSince1970: 100),
    modifyTime: Date? = Date(timeIntervalSince1970: 200),
    createTime: Date? = Date(timeIntervalSince1970: 300)
) -> FPItem {
    FPItem(
        item: Item(
            id: id,
            parentId: parentId,
            name: name,
            kind: kind,
            size: size,
            flags: flags,
            accessTime: accessTime,
            modifyTime: modifyTime,
            createTime: createTime,
            enumeratedAt: nil
        )
    )
}

struct FPItemIdentityTests {
    @Test func itemIdentifierMatchesItemId() {
        #expect(makeItem(id: "abc").itemIdentifier.rawValue == "abc")
    }

    @Test func parentItemIdentifierMatchesItemParentId() {
        #expect(makeItem(parentId: "p").parentItemIdentifier.rawValue == "p")
    }

    @Test func nilParentIdMapsToRootContainer() {
        #expect(makeItem(parentId: nil).parentItemIdentifier == .rootContainer)
    }

    @Test func filenameMatchesItemName() {
        #expect(makeItem(name: "notes.md").filename == "notes.md")
    }
}

struct FPItemContentTypeTests {
    @Test(arguments: [
        ("file.txt", UTType.plainText),
        ("notes.md", UTType("net.daringfireball.markdown")!),
        ("image.png", UTType.png),
        ("archive.zip", UTType.zip),
        ("archive.tar.gz", UTType.gzip),
    ])
    func knownExtensionReportsDeclaredType(name: String, expected: UTType) {
        #expect(makeItem(name: name, kind: .file).contentType == expected)
    }

    @Test func unknownExtensionReportsDynamicDataType() {
        let type = makeItem(name: "file.foo", kind: .file).contentType
        #expect(type.isDynamic)
        #expect(type.conforms(to: .data))
    }

    @Test func noExtensionReportsData() {
        #expect(makeItem(name: "Makefile", kind: .file).contentType == .data)
    }

    @Test(arguments: ["a.dSYM", "a.app", "a.rtfd", "a.bundle"])
    func packageExtensionOnFileIsNotPackage(name: String) {
        let type = makeItem(name: name, kind: .file).contentType
        #expect(type.conforms(to: .data))
        #expect(!type.conforms(to: .package))
    }

    @Test(arguments: [
        ("a.dSYM", "com.apple.xcode.dsym"),
        ("a.app", "com.apple.application-bundle"),
        ("a.bundle", "com.apple.generic-bundle"),
        ("a.rtfd", "com.apple.rtfd"),
    ])
    func packageExtensionReportsPackageType(name: String, expected: String) {
        let type = makeItem(name: name, kind: .folder).contentType
        #expect(type.identifier == expected)
        #expect(type.conforms(to: .package))
    }

    @Test func nonPackageBundleReportsDeclaredType() {
        let type = makeItem(name: "a.framework", kind: .folder).contentType
        #expect(type.identifier == "com.apple.framework")
        #expect(!type.conforms(to: .package))
    }

    @Test func noExtensionReportsFolder() {
        #expect(makeItem(name: "docs", kind: .folder).contentType == .folder)
    }

    @Test func unknownExtensionReportsFolder() {
        #expect(makeItem(name: "a.foo", kind: .folder).contentType == .folder)
    }

    @Test func dataExtensionReportsFolder() {
        #expect(
            makeItem(name: "file.txt", kind: .folder).contentType == .folder
        )
    }

    @Test func renameIntoPackageExtensionChangesType() {
        #expect(makeItem(name: "a", kind: .folder).contentType == .folder)
        #expect(
            makeItem(name: "a.dSYM", kind: .folder).contentType
                .conforms(to: .package)
        )
    }

    @Test(arguments: ["link", "link.md", "link.txt", "link.dSYM"])
    func contentTypeIsSymbolicLinkRegardlessOfExtension(name: String) {
        let item = makeItem(name: name, kind: .symlink(target: "target"))
        #expect(item.contentType == .symbolicLink)
    }
}

struct FPItemVersionTests {
    @Test func versionIsStableForEqualItems() {
        let a = makeItem().itemVersion
        let b = makeItem().itemVersion
        #expect(a.contentVersion == b.contentVersion)
        #expect(a.metadataVersion == b.metadataVersion)
    }

    @Test func contentChangeOnlyChangesContentVersion() {
        let a = makeItem(size: 1024).itemVersion
        let b = makeItem(size: 2048).itemVersion
        #expect(a.contentVersion != b.contentVersion)
        #expect(a.metadataVersion == b.metadataVersion)
    }

    @Test func renameOnlyChangesMetadataVersion() {
        let a = makeItem(name: "a.txt").itemVersion
        let b = makeItem(name: "b.txt").itemVersion
        #expect(a.contentVersion == b.contentVersion)
        #expect(a.metadataVersion != b.metadataVersion)
    }
}
