import FileProvider
import Testing

@testable import Common

struct ItemFlagsTests {
    @Test func readableWritableModeIs600() {
        let flags: Item.Flags = .rw
        #expect(flags.mode == 0o600)
    }

    @Test func readableModeIs400() {
        let flags: Item.Flags = [.readable]
        #expect(flags.mode == 0o400)
    }

    @Test func writableModeIs200() {
        let flags: Item.Flags = [.writable]
        #expect(flags.mode == 0o200)
    }

    @Test func executableModeIs100() {
        let flags: Item.Flags = [.executable]
        #expect(flags.mode == 0o100)
    }

    @Test func emptyModeIs000() {
        let flags: Item.Flags = []
        #expect(flags.mode == 0o000)
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
