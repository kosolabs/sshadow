import Common
import IgnoreModule
import Testing

@testable import CoreKit

private let ignore = ".sshadowignore"

struct IgnoreCacheTests {
    @Test func unknownRootIgnoresNothing() {
        let cache = IgnoreCache(filenames: [ignore])
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
    }

    @Test func unknownChildIgnoresNothing() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: .contents("*.log\n")]))
        #expect(cache.rule(ignoring: "a.log", in: "src", isDirectory: false) == nil)
    }

    @Test func knowsRecordedDirectories() {
        var cache = IgnoreCache(filenames: [ignore])
        #expect(!cache.knows(""))

        cache.update(IgnoreFiles(children: ["src": IgnoreFiles()]))

        #expect(cache.knows(""))
        #expect(cache.knows("src"))
        #expect(!cache.knows("src/lib"))
    }

    @Test func rulesApplyFromEachLevel() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(
            IgnoreFiles(
                files: [ignore: .contents("build/\n")],
                children: [
                    "src": IgnoreFiles(children: [
                        "lib": IgnoreFiles(files: [ignore: .contents("*.log\n")])
                    ])
                ]
            )
        )

        let build = cache.rule(ignoring: "build", in: "src/lib", isDirectory: true)
        let log = cache.rule(ignoring: "debug.log", in: "src/lib", isDirectory: false)
        let source = cache.rule(ignoring: "main.c", in: "src/lib", isDirectory: false)

        #expect(build?.from == ignore)
        #expect(build?.original == "build/")
        #expect(log?.from == "src/lib/\(ignore)")
        #expect(log?.original == "*.log")
        #expect(source == nil)
    }

    @Test func ignoredAncestorIgnoresEverythingBelow() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(
            IgnoreFiles(
                files: [ignore: .contents("data/\n")],
                children: ["data": IgnoreFiles(children: ["sub": IgnoreFiles()])]
            )
        )

        let rule = cache.rule(ignoring: "a.txt", in: "data/sub", isDirectory: false)

        #expect(rule?.original == "data/")
    }

    @Test func whitelistedIgnoresNothing() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: .contents("*.log\n!keep.log\n")]))
        #expect(cache.rule(ignoring: "keep.log", in: "", isDirectory: false) == nil)
    }

    @Test func onlyConfiguredFilenamesApply() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [".gitignore": .contents("build/\n")]))
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
    }

    @Test func unknownRemoteFileHasNoRules() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: .remote]))
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
    }

    @Test func firstUpdateIsNotAChange() {
        var cache = IgnoreCache(filenames: [ignore])
        let changed = cache.update(IgnoreFiles(files: [ignore: .contents("build/\n")]))
        #expect(changed == [])
    }

    @Test func changedRulesApplyToDescendants() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(
            IgnoreFiles(files: [ignore: .contents("*.log\n")], children: ["src": IgnoreFiles()])
        )
        let before = cache.rule(ignoring: "a.log", in: "src", isDirectory: false)

        cache.update(IgnoreFiles())
        let after = cache.rule(ignoring: "a.log", in: "src", isDirectory: false)

        #expect(before != nil)
        #expect(after == nil)
    }
}
