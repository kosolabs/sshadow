import Common
import Foundation
import Ignore
import Testing

@testable import CoreKit

private let ignore = ".sshadowignore"

private func text(_ contents: String, at seconds: TimeInterval = 0) -> IgnoreFile {
    .contents(contents, modified: Date(timeIntervalSince1970: seconds))
}

private func branch(_ root: IgnoreFile?, _ lib: IgnoreFile?) -> IgnoreFiles {
    IgnoreFiles(
        files: root.map { [ignore: $0] } ?? [:],
        children: [
            "src": IgnoreFiles(children: [
                "lib": IgnoreFiles(files: lib.map { [ignore: $0] } ?? [:])
            ])
        ]
    )
}

extension IgnoreCache {
    fileprivate func ignores(_ name: String, in dir: String = "") -> Bool {
        rule(ignoring: name, in: dir, isDirectory: false) != nil
    }
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

        #expect(build?.file == ignore)
        #expect(build?.original == "build/")
        #expect(log?.file == "src/lib/\(ignore)")
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

    @Test func mergeReportsChangedDirectories() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(branch(text("a\n", at: 10), nil), from: .remote)
        let same = cache.update(branch(text("a\n", at: 10), nil), from: .remote)
        let changed = cache.update(
            branch(text("b\n", at: 20), text("c\n", at: 20)),
            from: .remote
        )
        let removed = cache.update(branch(nil, text("c\n", at: 20)), from: .remote)

        #expect(same == [])
        #expect(changed == ["", "src/lib"])
        #expect(removed == [""])
        #expect(!cache.ignores("b"))
        #expect(cache.ignores("c", in: "src/lib"))
    }

    @Test func newDirectoryIsNotAChange() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(), from: .remote)
        let changed = cache.update(
            IgnoreFiles(children: ["src": IgnoreFiles(files: [ignore: text("a\n")])]),
            from: .local
        )

        #expect(changed == [])
        #expect(cache.ignores("a", in: "src"))
    }

    @Test func olderLocalCopyKeepsNewerRules() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("new\n", at: 20)]), from: .remote)
        let changed = cache.update(
            IgnoreFiles(files: [ignore: text("old\n", at: 10)]),
            from: .local
        )

        #expect(changed == [])
        #expect(cache.ignores("new"))
        #expect(!cache.ignores("old"))
    }

    @Test func newerLocalCopyWins() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("old\n", at: 10)]), from: .remote)
        let changed = cache.update(
            IgnoreFiles(files: [ignore: text("new\n", at: 20)]),
            from: .local
        )

        #expect(changed == [""])
        #expect(cache.ignores("new"))
        #expect(!cache.ignores("old"))
    }

    @Test func olderRemoteCopyKeepsNewerLocalEdit() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("edit\n", at: 30)]), from: .local)
        let changed = cache.update(
            IgnoreFiles(files: [ignore: text("old\n", at: 20)]),
            from: .remote
        )

        #expect(changed == [])
        #expect(cache.ignores("edit"))
    }

    @Test func copiesFromTheSameSecondKeepKnownRules() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("a\n", at: 10.2)]), from: .remote)
        let changed = cache.update(
            IgnoreFiles(files: [ignore: text("b\n", at: 10.9)]),
            from: .local
        )

        #expect(changed == [])
        #expect(cache.ignores("a"))
    }

    @Test func fileMissingLocallyKeepsRules() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("a\n")]), from: .remote)
        let changed = cache.update(IgnoreFiles(), from: .local)

        #expect(changed == [])
        #expect(cache.ignores("a"))
    }

    @Test func fileMissingRemotelyDropsRules() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("a\n")]), from: .remote)
        let changed = cache.update(IgnoreFiles(), from: .remote)

        #expect(changed == [""])
        #expect(!cache.ignores("a"))
    }

    @Test func remoteFileKeepsKnownContents() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(files: [ignore: text("a\n")]), from: .remote)
        let local = cache.update(IgnoreFiles(files: [ignore: .remote]), from: .local)
        let remote = cache.update(IgnoreFiles(files: [ignore: .remote]), from: .remote)

        #expect(local == [])
        #expect(remote == [])
        #expect(cache.ignores("a"))
    }

    @Test func remoteFileWithoutKnownContentsIsDropped() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(IgnoreFiles(), from: .remote)
        let changed = cache.update(
            IgnoreFiles(
                files: [ignore: .remote],
                children: ["src": IgnoreFiles(files: [ignore: .remote])]
            ),
            from: .local
        )

        #expect(changed == [])
        #expect(cache.knows("src"))
        #expect(!cache.ignores("a", in: "src"))
    }

    @Test func mergeLeavesSiblingsAlone() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(
            IgnoreFiles(children: ["srcs": IgnoreFiles(files: [ignore: text("*.o\n")])]),
            from: .remote
        )
        cache.update(IgnoreFiles(children: ["src": IgnoreFiles()]), from: .remote)

        #expect(cache.ignores("a.o", in: "srcs"))
    }

    @Test func removeForgetsNestedFile() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(branch(nil, text("a\n")), from: .remote)

        let removed = cache.remove(ignore, in: "src/lib")
        let again = cache.remove(ignore, in: "src/lib")
        let missing = cache.remove(ignore, in: "missing")

        #expect(removed)
        #expect(!again)
        #expect(!missing)
        #expect(!cache.ignores("a", in: "src/lib"))
    }
}
