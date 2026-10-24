import Common
import Foundation
import Ignore
import Testing

@testable import CoreKit

private let ignore = ".sshadowignore"

private func text(_ contents: String) -> IgnoreFile {
    .contents(contents)
}

private func branch(
    _ root: IgnoreFile?,
    _ lib: IgnoreFile?
) -> [FolderIgnoreFiles] {
    [
        ("", root.map { [ignore: $0] } ?? [:]),
        ("src", [:]),
        ("src/lib", lib.map { [ignore: $0] } ?? [:]),
    ]
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
        cache.update([("", [ignore: text("*.log\n")])])
        #expect(
            cache.rule(ignoring: "a.log", in: "src", isDirectory: false) == nil
        )
    }

    @Test func knowsRecordedDirectories() {
        var cache = IgnoreCache(filenames: [ignore])
        #expect(!cache.knows(""))

        cache.update([("", [:]), ("src", [:])])

        #expect(cache.knows(""))
        #expect(cache.knows("src"))
        #expect(!cache.knows("src/lib"))
    }

    @Test func rulesApplyFromEachLevel() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([
            ("", [ignore: text("build/\n")]),
            ("src", [:]),
            ("src/lib", [ignore: text("*.log\n")]),
        ])

        let build = cache.rule(
            ignoring: "build",
            in: "src/lib",
            isDirectory: true
        )
        let log = cache.rule(
            ignoring: "debug.log",
            in: "src/lib",
            isDirectory: false
        )
        let source = cache.rule(
            ignoring: "main.c",
            in: "src/lib",
            isDirectory: false
        )

        #expect(build?.file == ignore)
        #expect(build?.original == "build/")
        #expect(log?.file == "src/lib/\(ignore)")
        #expect(log?.original == "*.log")
        #expect(source == nil)
    }

    @Test func ignoredAncestorIgnoresEverythingBelow() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([
            ("", [ignore: text("data/\n")]),
            ("data", [:]),
            ("data/sub", [:]),
        ])

        let rule = cache.rule(
            ignoring: "a.txt",
            in: "data/sub",
            isDirectory: false
        )

        #expect(rule?.original == "data/")
    }

    @Test func whitelistedIgnoresNothing() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [ignore: text("*.log\n!keep.log\n")])])
        #expect(
            cache.rule(ignoring: "keep.log", in: "", isDirectory: false) == nil
        )
    }

    @Test func onlyConfiguredFilenamesApply() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [".gitignore": text("build/\n")])])
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
    }

    @Test func unresolvedFileInUnknownFolderHasNoRules() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [ignore: .unresolved])])
        #expect(cache.rule(ignoring: "build", in: "", isDirectory: true) == nil)
    }

    @Test func firstUpdateIsNotAChange() {
        var cache = IgnoreCache(filenames: [ignore])
        let changed = cache.update([("", [ignore: text("build/\n")])])
        #expect(changed == [])
    }

    @Test func changedRulesApplyToDescendants() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [ignore: text("*.log\n")]), ("src", [:])])
        let before = cache.rule(
            ignoring: "a.log",
            in: "src",
            isDirectory: false
        )

        cache.update([("", [:])])
        let after = cache.rule(ignoring: "a.log", in: "src", isDirectory: false)

        #expect(before != nil)
        #expect(after == nil)
    }

    @Test func mergeReportsChangedDirectories() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update(branch(text("a\n"), nil))
        let same = cache.update(branch(text("a\n"), nil))
        let changed = cache.update(
            branch(text("b\n"), text("c\n"))
        )
        let removed = cache.update(branch(nil, text("c\n")))

        #expect(same == [])
        #expect(changed == ["", "src/lib"])
        #expect(removed == [""])
        #expect(!cache.ignores("b"))
        #expect(cache.ignores("c", in: "src/lib"))
    }

    @Test func newDirectoryIsNotAChange() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [:])])
        let changed = cache.update([("", [:]), ("src", [ignore: text("a\n")])])

        #expect(changed == [])
        #expect(cache.ignores("a", in: "src"))
    }

    @Test func fileMissingRemotelyDropsRules() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [ignore: text("a\n")])])
        let changed = cache.update([("", [:])])

        #expect(changed == [""])
        #expect(!cache.ignores("a"))
    }

    @Test func unresolvedFileKeepsKnownContents() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [ignore: text("a\n")])])
        let changed = cache.update([("", [ignore: .unresolved])])

        #expect(changed == [])
        #expect(cache.ignores("a"))
    }

    @Test func unresolvedFileWithoutKnownContentsIsDropped() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [:])])
        let changed = cache.update([
            ("", [ignore: .unresolved]),
            ("src", [ignore: .unresolved]),
        ])

        #expect(changed == [])
        #expect(cache.knows("src"))
        #expect(!cache.ignores("a", in: "src"))
    }

    @Test func mergeLeavesSiblingsAlone() {
        var cache = IgnoreCache(filenames: [ignore])
        cache.update([("", [:]), ("srcs", [ignore: text("*.o\n")])])
        cache.update([("", [:]), ("src", [:])])

        #expect(cache.ignores("a.o", in: "srcs"))
    }

    @Test func ancestorsListParentFoldersFromTheRoot() {
        #expect(ancestors(of: "") == [])
        #expect(ancestors(of: "src") == [""])
        #expect(ancestors(of: "src/lib") == ["", "src"])
    }
}
