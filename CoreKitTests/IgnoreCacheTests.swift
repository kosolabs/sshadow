import Common
import Foundation
import IgnoreModule
import Testing

@testable import CoreKit

private let ignore = ".sshadowignore"

private func text(_ contents: String, at seconds: TimeInterval = 0) -> IgnoreFile {
    .contents(contents, modified: Date(timeIntervalSince1970: seconds))
}

struct IgnoreCacheTests {
    @Test func unknownRootIgnoresNothing() {
        let cache = IgnoreCache(filenames: [ignore])
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
    }

    @Test func unknownChildIgnoresNothing() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("*.log\n")]), from: .remote)
        #expect(cache.rule(ignoring: "a.log", in: "src", isDirectory: false) == nil)
    }

    @Test func knowsRecordedDirectories() {
        var cache = IgnoreCache(filenames: [ignore])
        #expect(!cache.knows(""))

        cache.update(IgnoreFiles(children: ["src": IgnoreFiles()]), from: .remote)

        #expect(cache.knows(""))
        #expect(cache.knows("src"))
        #expect(!cache.knows("src/lib"))
    }

    @Test func rulesApplyFromEachLevel() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(
            IgnoreFiles(
                files: [ignore: text("build/\n")],
                children: [
                    "src": IgnoreFiles(children: [
                        "lib": IgnoreFiles(files: [ignore: text("*.log\n")])
                    ])
                ]
            ),
            from: .remote
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
                files: [ignore: text("data/\n")],
                children: ["data": IgnoreFiles(children: ["sub": IgnoreFiles()])]
            ),
            from: .remote
        )

        let rule = cache.rule(ignoring: "a.txt", in: "data/sub", isDirectory: false)

        #expect(rule?.original == "data/")
    }

    @Test func whitelistedIgnoresNothing() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("*.log\n!keep.log\n")]), from: .remote)
        #expect(cache.rule(ignoring: "keep.log", in: "", isDirectory: false) == nil)
    }

    @Test func onlyConfiguredFilenamesApply() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [".gitignore": text("build/\n")]), from: .remote)
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
    }

    @Test func unknownRemoteFileHasNoRules() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: .remote]), from: .remote)
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
    }

    @Test func firstUpdateIsNotAChange() {
        var cache = IgnoreCache(filenames: [ignore])
        let changed = cache.update(IgnoreFiles(files: [ignore: text("build/\n")]), from: .remote)
        #expect(changed == [])
    }

    @Test func lastChangeAffectingDirectoryRecordsItsOrigin() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(children: ["src": IgnoreFiles()]), from: .remote)
        #expect(cache.lastChange(affecting: "src") == nil)

        cache.update(
            IgnoreFiles(children: ["src": IgnoreFiles(files: [ignore: text("a\n", at: 10)])]),
            from: .local
        )
        #expect(cache.lastChange(affecting: "src") == .local)
        #expect(cache.lastChange(affecting: "") == nil)

        cache.update(
            IgnoreFiles(files: [ignore: text("b\n", at: 20)], children: ["src": IgnoreFiles()]),
            from: .remote
        )
        #expect(cache.lastChange(affecting: "src") == .remote)
        #expect(cache.lastChange(affecting: "") == .remote)
    }

    @Test func removeForgetsRulesAsALocalChange() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("build/\n")]), from: .remote)

        let removed = cache.remove(ignore, in: "")
        let again = cache.remove(ignore, in: "")

        #expect(removed)
        #expect(!again)
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
        #expect(cache.lastChange(affecting: "") == .local)
    }

    @Test func changedRulesApplyToDescendants() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(
            IgnoreFiles(files: [ignore: text("*.log\n")], children: ["src": IgnoreFiles()]),
            from: .remote
        )
        let before = cache.rule(ignoring: "a.log", in: "src", isDirectory: false)

        cache.update(IgnoreFiles(), from: .remote)
        let after = cache.rule(ignoring: "a.log", in: "src", isDirectory: false)

        #expect(before != nil)
        #expect(after == nil)
    }
}
