import FileProvider
import Testing

@testable import Common

private func makeItem(
    id: String = "id",
    parentId: String? = "parent",
    name: String = "file.txt",
    kind: Item.Kind = .file,
    size: UInt64? = 1024,
    flags: Item.Flags? = .rw,
    accessTime: Date? = Date(timeIntervalSince1970: 100),
    modifyTime: Date? = Date(timeIntervalSince1970: 200),
    createTime: Date? = Date(timeIntervalSince1970: 300),
    enumeratedAt: Date? = nil
) -> Item {
    Item(
        id: id,
        parentId: parentId,
        name: name,
        kind: kind,
        size: size,
        flags: flags,
        accessTime: accessTime,
        modifyTime: modifyTime,
        createTime: createTime,
        enumeratedAt: enumeratedAt
    )
}

struct ItemFlagsTests {
    @Test func readableWritableModeIs666() {
        let flags: Item.Flags = .rw
        #expect(flags.mode == 0o666)
    }

    @Test func readableModeIs444() {
        let flags: Item.Flags = [.readable]
        #expect(flags.mode == 0o444)
    }

    @Test func writableModeIs222() {
        let flags: Item.Flags = [.writable]
        #expect(flags.mode == 0o222)
    }

    @Test func executableModeIs111() {
        let flags: Item.Flags = [.executable]
        #expect(flags.mode == 0o111)
    }

    @Test func emptyModeIs000() {
        let flags: Item.Flags = []
        #expect(flags.mode == 0o000)
    }

    @Test func modeWithUmask022MasksGroupAndOtherWriteBits() {
        let flags: Item.Flags = .rw
        #expect(flags.mode(umask: 0o022) == 0o644)
    }

    @Test func modeWithUmask022OnAllYields755() {
        let flags: Item.Flags = .all
        #expect(flags.mode(umask: 0o022) == 0o755)
    }

    @Test func modeWithUmask077RestrictsToOwner() {
        let flags: Item.Flags = .all
        #expect(flags.mode(umask: 0o077) == 0o700)
    }

    @Test func modeWithZeroUmaskIsUnchanged() {
        let flags: Item.Flags = .rw
        #expect(flags.mode(umask: 0o000) == flags.mode)
    }

    @Test func modeWithUmask777MasksAllBits() {
        let flags: Item.Flags = .all
        #expect(flags.mode(umask: 0o777) == 0o000)
    }

    @Test func fromMode600IsReadableWritable() {
        let flags = Item.Flags(from: 0o600)
        #expect(flags == [.readable, .writable])
    }

    @Test func fromMode400IsReadable() {
        let flags = Item.Flags(from: 0o400)
        #expect(flags == [.readable])
    }

    @Test func fromMode200IsWritable() {
        let flags = Item.Flags(from: 0o200)
        #expect(flags == [.writable])
    }

    @Test func fromMode100IsExecutable() {
        let flags = Item.Flags(from: 0o100)
        #expect(flags == [.executable])
    }

    @Test func fromMode000IsEmpty() {
        let flags = Item.Flags(from: 0o000)
        #expect(flags == [])
    }

    @Test func fromMode755IgnoresGroupAndOtherBits() {
        let flags = Item.Flags(from: 0o755)
        #expect(flags == .all)
    }
}

struct ContentVersionTests {
    @Test func contentVersionIsStableForEqualContent() {
        #expect(makeItem().contentVersion == makeItem().contentVersion)
    }

    @Test func contentVersionChangesWithSize() {
        #expect(
            makeItem(size: 1024).contentVersion
                != makeItem(size: 2048).contentVersion
        )
    }

    @Test func contentVersionChangesWithModifyTime() {
        let a = makeItem(modifyTime: Date(timeIntervalSince1970: 200))
        let b = makeItem(modifyTime: Date(timeIntervalSince1970: 201))
        #expect(a.contentVersion != b.contentVersion)
    }

    @Test func contentVersionIgnoresMetadataOnlyFields() {
        let a = makeItem(
            name: "a.txt",
            flags: .rw,
            createTime: Date(timeIntervalSince1970: 300)
        )
        let b = makeItem(
            name: "b.txt",
            flags: .all,
            createTime: Date(timeIntervalSince1970: 999)
        )
        #expect(a.contentVersion == b.contentVersion)
    }

    @Test func contentVersionChangesWhenSizeBecomesNil() {
        #expect(
            makeItem(size: 1024).contentVersion
                != makeItem(size: nil).contentVersion
        )
    }
}

struct MetadataVersionTests {
    @Test func metadataVersionIsStableForEqualMetadata() {
        #expect(makeItem().metadataVersion == makeItem().metadataVersion)
    }

    @Test func metadataVersionChangesWithName() {
        #expect(
            makeItem(name: "a.txt").metadataVersion
                != makeItem(name: "b.txt").metadataVersion
        )
    }

    @Test func metadataVersionChangesWithParentId() {
        #expect(
            makeItem(parentId: "a").metadataVersion
                != makeItem(parentId: "b").metadataVersion
        )
    }

    @Test func metadataVersionChangesWithFlags() {
        #expect(
            makeItem(flags: .rw).metadataVersion
                != makeItem(flags: .all).metadataVersion
        )
    }

    @Test func metadataVersionChangesWithModifyTime() {
        let a = makeItem(modifyTime: Date(timeIntervalSince1970: 200))
        let b = makeItem(modifyTime: Date(timeIntervalSince1970: 201))
        #expect(a.metadataVersion != b.metadataVersion)
    }

    @Test func metadataVersionChangesWithCreateTime() {
        let a = makeItem(createTime: Date(timeIntervalSince1970: 300))
        let b = makeItem(createTime: Date(timeIntervalSince1970: 301))
        #expect(a.metadataVersion != b.metadataVersion)
    }

    @Test func metadataVersionIgnoresContentOnlyFields() {
        let a = makeItem(
            size: 1024,
            accessTime: Date(timeIntervalSince1970: 100)
        )
        let b = makeItem(
            size: 2048,
            accessTime: Date(timeIntervalSince1970: 999)
        )
        #expect(a.metadataVersion == b.metadataVersion)
    }

    @Test func metadataVersionChangesWhenParentIdBecomesNil() {
        #expect(
            makeItem(parentId: "parent").metadataVersion
                != makeItem(parentId: nil).metadataVersion
        )
    }
}
