import Common
import Foundation
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

struct IgnoreFilesMergeTests {
    @Test func mergeReportsChangedDirectories() {
        var tree = branch(text("a\n", at: 10), nil)
        let same = tree.merge(branch(text("a\n", at: 10), nil), from: .remote)
        let changed = tree.merge(
            branch(text("b\n", at: 20), text("c\n", at: 20)),
            from: .remote
        )
        let removed = tree.merge(branch(nil, text("c\n", at: 20)), from: .remote)

        #expect(same == [])
        #expect(changed == ["", "src/lib"])
        #expect(removed == [""])
        #expect(tree == branch(nil, text("c\n", at: 20)))
    }

    @Test func newDirectoryIsNotAChange() {
        var tree = IgnoreFiles()
        let changed = tree.merge(
            IgnoreFiles(children: ["src": IgnoreFiles(files: [ignore: text("a\n")])]),
            from: .local
        )

        #expect(changed == [])
        #expect(tree.children["src"]?.files == [ignore: text("a\n")])
    }

    @Test func olderLocalCopyKeepsNewerRules() {
        var tree = IgnoreFiles(files: [ignore: text("new\n", at: 20)])
        let changed = tree.merge(IgnoreFiles(files: [ignore: text("old\n", at: 10)]), from: .local)

        #expect(changed == [])
        #expect(tree.files == [ignore: text("new\n", at: 20)])
    }

    @Test func newerLocalCopyWins() {
        var tree = IgnoreFiles(files: [ignore: text("old\n", at: 10)])
        let changed = tree.merge(IgnoreFiles(files: [ignore: text("new\n", at: 20)]), from: .local)

        #expect(changed == [""])
        #expect(tree.files == [ignore: text("new\n", at: 20)])
    }

    @Test func olderRemoteCopyKeepsNewerLocalEdit() {
        var tree = IgnoreFiles(files: [ignore: text("edit\n", at: 30)])
        let changed = tree.merge(IgnoreFiles(files: [ignore: text("old\n", at: 20)]), from: .remote)

        #expect(changed == [])
        #expect(tree.files == [ignore: text("edit\n", at: 30)])
    }

    @Test func copiesFromTheSameSecondKeepKnownRules() {
        var tree = IgnoreFiles(files: [ignore: text("a\n", at: 10.2)])
        let changed = tree.merge(IgnoreFiles(files: [ignore: text("b\n", at: 10.9)]), from: .local)

        #expect(changed == [])
    }

    @Test func fileMissingLocallyKeepsRules() {
        var tree = IgnoreFiles(files: [ignore: text("a\n")])
        let changed = tree.merge(IgnoreFiles(), from: .local)

        #expect(changed == [])
        #expect(tree.files == [ignore: text("a\n")])
    }

    @Test func fileMissingRemotelyDropsRules() {
        var tree = IgnoreFiles(files: [ignore: text("a\n")])
        let changed = tree.merge(IgnoreFiles(), from: .remote)

        #expect(changed == [""])
        #expect(tree.files == [:])
    }

    @Test func remoteFileKeepsKnownContents() {
        var tree = IgnoreFiles(files: [ignore: text("a\n")])
        let local = tree.merge(IgnoreFiles(files: [ignore: .remote]), from: .local)
        let remote = tree.merge(IgnoreFiles(files: [ignore: .remote]), from: .remote)

        #expect(local == [])
        #expect(remote == [])
        #expect(tree.files == [ignore: text("a\n")])
    }

    @Test func remoteFileWithoutKnownContentsIsDropped() {
        var tree = IgnoreFiles()
        let changed = tree.merge(
            IgnoreFiles(
                files: [ignore: .remote],
                children: ["src": IgnoreFiles(files: [ignore: .remote])]
            ),
            from: .local
        )

        #expect(changed == [])
        #expect(tree == IgnoreFiles(children: ["src": IgnoreFiles()]))
    }

    @Test func mergeLeavesSiblingsAlone() {
        let srcs = IgnoreFiles(files: [ignore: text("*.o\n")])
        var tree = IgnoreFiles(children: ["srcs": srcs])
        _ = tree.merge(IgnoreFiles(children: ["src": IgnoreFiles()]), from: .remote)

        #expect(tree.children["srcs"] == srcs)
    }

    @Test func removeForgetsFile() {
        var tree = branch(nil, text("a\n"))

        let removed = tree.remove(ignore, in: ["src", "lib"])
        let again = tree.remove(ignore, in: ["src", "lib"])
        let missing = tree.remove(ignore, in: ["missing"])

        #expect(removed)
        #expect(!again)
        #expect(!missing)
        #expect(tree == branch(nil, nil))
    }

    @Test func knownDropsRemoteFiles() {
        let tree = IgnoreFiles(
            files: [ignore: .remote, ".gitignore": text("a\n")],
            children: ["src": IgnoreFiles(files: [ignore: .remote])]
        )

        #expect(
            tree.known
                == IgnoreFiles(
                    files: [".gitignore": text("a\n")],
                    children: ["src": IgnoreFiles()]
                )
        )
    }

    @Test func branchInitNestsEachLevel() {
        let tree = IgnoreFiles(
            branch: ["src", "lib"],
            files: [[ignore: text("a\n")], [:], [ignore: text("b\n")]]
        )
        #expect(tree == branch(text("a\n"), text("b\n")))
    }

    @Test func branchListsDirectoryNames() {
        #expect(IgnoreFiles().branch == [])
        #expect(branch(nil, nil).branch == ["src", "lib"])
    }

    @Test func treeWithSiblingsIsNotABranch() {
        let tree = IgnoreFiles(children: ["a": IgnoreFiles(), "b": IgnoreFiles()])
        #expect(tree.branch == nil)
    }
}
