import Testing

@testable import Common

struct FlagTests {
    @Test func initialValueFalse() {
        #expect(!Flag(false).isSet)
    }

    @Test func initialValueTrue() {
        #expect(Flag(true).isSet)
    }

    @Test func setMakesIsSetTrue() {
        let flag = Flag(false)
        flag.set()
        #expect(flag.isSet)
    }

    @Test func clearMakesIsSetFalse() {
        let flag = Flag(true)
        flag.clear()
        #expect(!flag.isSet)
    }

    @Test func setIsIdempotent() {
        let flag = Flag(false)
        flag.set()
        flag.set()
        #expect(flag.isSet)
    }

    @Test func clearIsIdempotent() {
        let flag = Flag(true)
        flag.clear()
        flag.clear()
        #expect(!flag.isSet)
    }

    @Test func setThenClear() {
        let flag = Flag(false)
        flag.set()
        flag.clear()
        #expect(!flag.isSet)
    }
}
