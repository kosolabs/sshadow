import Common
import Foundation
import Ignore
import Testing

@testable import CoreKit

private let ignore = ".sshadowignore"

private func text(
    _ contents: String,
    named name: String = ignore,
    version: IgnoreFile.Version = version
) -> IgnoreFile {
    IgnoreFile(name: name, content: .loaded(contents, version: version))
}

private func unresolved(_ name: String = ignore) -> IgnoreFile {
    IgnoreFile(name: name, content: .unresolved)
}

private func folder(_ path: String, _ files: IgnoreFile...) -> IgnoreFolder {
    IgnoreFolder(path: path, files: files)
}

private func branch(
    _ root: IgnoreFile?,
    _ lib: IgnoreFile?
) -> IgnoreSnapshot {
    [
        IgnoreFolder(path: "", files: root.map { [$0] } ?? []),
        folder("src"),
        IgnoreFolder(path: "src/lib", files: lib.map { [$0] } ?? []),
    ]
}

private let version = IgnoreFile.Version(
    modifyTime: Date(timeIntervalSince1970: 1),
    size: 6
)

private let newer = IgnoreFile.Version(
    modifyTime: Date(timeIntervalSince1970: 2),
    size: 6
)

extension Ignores {
    fileprivate func ignore(_ name: String, in dir: String = "") -> Bool {
        rule(ignoring: name, in: dir, isDirectory: false) != nil
    }
}

struct IgnoreCacheTests {
    @Test func unknownRootIgnoresNothing() {
        let ignores = Ignores(filenames: [ignore])
        #expect(
            ignores.rule(ignoring: "build", in: "", isDirectory: true) == nil
        )
    }

    @Test func unknownChildIgnoresNothing() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("*.log\n"))])
        #expect(
            ignores.rule(ignoring: "a.log", in: "src", isDirectory: false)
                == nil
        )
    }

    @Test func knowsRecordedDirectories() {
        var ignores = Ignores(filenames: [ignore])
        #expect(!ignores.knows(""))

        ignores.update([folder(""), folder("src")])

        #expect(ignores.knows(""))
        #expect(ignores.knows("src"))
        #expect(!ignores.knows("src/lib"))
    }

    @Test func rulesApplyFromEachLevel() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([
            folder("", text("build/\n")),
            folder("src"),
            folder("src/lib", text("*.log\n")),
        ])

        let build = ignores.rule(
            ignoring: "build",
            in: "src/lib",
            isDirectory: true
        )
        let log = ignores.rule(
            ignoring: "debug.log",
            in: "src/lib",
            isDirectory: false
        )
        let source = ignores.rule(
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
        var ignores = Ignores(filenames: [ignore])
        ignores.update([
            folder("", text("data/\n")),
            folder("data"),
            folder("data/sub"),
        ])

        let rule = ignores.rule(
            ignoring: "a.txt",
            in: "data/sub",
            isDirectory: false
        )

        #expect(rule?.original == "data/")
    }

    @Test func whitelistedIgnoresNothing() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("*.log\n!keep.log\n"))])
        #expect(
            ignores.rule(ignoring: "keep.log", in: "", isDirectory: false)
                == nil
        )
    }

    @Test func onlyConfiguredFilenamesApply() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("build/\n", named: ".gitignore"))])
        #expect(
            ignores.rule(ignoring: "build", in: "", isDirectory: true) == nil
        )
    }

    @Test func laterFilenamesOverrideEarlierOnes() {
        var ignores = Ignores(filenames: [".gitignore", ignore])
        ignores.update([
            folder("", text("!keep.log\n"), text("*.log\n", named: ".gitignore"))
        ])

        #expect(ignores.ignore("a.log"))
        #expect(!ignores.ignore("keep.log"))
        #expect(!ignores.ignore("b.txt"))
    }

    @Test func unresolvedFileInUnknownFolderHasNoRules() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", unresolved())])
        #expect(
            ignores.rule(ignoring: "build", in: "", isDirectory: true) == nil
        )
    }

    @Test func firstUpdateIsNotAChange() {
        var ignores = Ignores(filenames: [ignore])
        let changed = ignores.update([folder("", text("build/\n"))])
        #expect(changed == [])
    }

    @Test func changedRulesApplyToDescendants() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("*.log\n")), folder("src")])
        let before = ignores.rule(
            ignoring: "a.log",
            in: "src",
            isDirectory: false
        )

        ignores.update([folder("")])
        let after = ignores.rule(
            ignoring: "a.log",
            in: "src",
            isDirectory: false
        )

        #expect(before != nil)
        #expect(after == nil)
    }

    @Test func mergeReportsChangedDirectories() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update(branch(text("a\n"), nil))
        let same = ignores.update(branch(text("a\n"), nil))
        let changed = ignores.update(
            branch(text("b\n"), text("c\n"))
        )
        let removed = ignores.update(branch(nil, text("c\n")))

        #expect(same == [])
        #expect(changed == ["", "src/lib"])
        #expect(removed == [""])
        #expect(!ignores.ignore("b"))
        #expect(ignores.ignore("c", in: "src/lib"))
    }

    @Test func newDirectoryIsNotAChange() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("")])
        let changed = ignores.update([folder(""), folder("src", text("a\n"))])

        #expect(changed == [])
        #expect(ignores.ignore("a", in: "src"))
    }

    @Test func fileMissingRemotelyDropsRules() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("a\n"))])
        let changed = ignores.update([folder("")])

        #expect(changed == [""])
        #expect(!ignores.ignore("a"))
    }

    @Test func unresolvedFileKeepsKnownContents() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("a\n"))])
        let changed = ignores.update([folder("", unresolved())])

        #expect(changed == [])
        #expect(ignores.ignore("a"))
    }

    @Test func unresolvedFileWithoutKnownContentsIsDropped() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("")])
        let changed = ignores.update(
            [folder("", unresolved()), folder("src", unresolved())]
        )

        #expect(changed == [])
        #expect(ignores.knows("src"))
        #expect(!ignores.ignore("a", in: "src"))
    }

    @Test func mergeLeavesSiblingsAlone() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder(""), folder("srcs", text("*.o\n"))])
        ignores.update([folder(""), folder("src")])

        #expect(ignores.ignore("a.o", in: "srcs"))
    }

    @Test func contentsVersionIsCurrent() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("*.log\n"))])

        #expect(ignores.isCurrent(ignore, in: "", at: version))
        #expect(!ignores.isCurrent(ignore, in: "", at: newer))
        #expect(!ignores.isCurrent(ignore, in: "src", at: version))
    }

    @Test func unresolvedFileKeepsVersion() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("*.log\n"))])

        ignores.update([folder("", unresolved())])

        #expect(ignores.isCurrent(ignore, in: "", at: version))
    }

    @Test func newContentsReplaceVersion() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("*.log\n"))])

        ignores.update([folder("", text("*.log\n", version: newer))])

        #expect(!ignores.isCurrent(ignore, in: "", at: version))
        #expect(ignores.isCurrent(ignore, in: "", at: newer))
    }

    @Test func removedFileClearsVersion() {
        var ignores = Ignores(filenames: [ignore])
        ignores.update([folder("", text("*.log\n"))])

        ignores.update([folder("")])

        #expect(!ignores.isCurrent(ignore, in: "", at: version))
    }

    @Test func ancestorsListParentFoldersFromTheRoot() {
        #expect(ancestors(of: "") == [])
        #expect(ancestors(of: "src") == [""])
        #expect(ancestors(of: "src/lib") == ["", "src"])
    }
}
