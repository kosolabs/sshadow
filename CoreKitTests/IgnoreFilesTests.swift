import Common
import Testing

@testable import CoreKit

private let ignore = ".sshadowignore"

private func branch(_ root: String?, _ lib: String?) -> IgnoreFiles {
    IgnoreFiles(
        files: root.map { [ignore: .contents($0)] } ?? [:],
        children: [
            "src": IgnoreFiles(children: [
                "lib": IgnoreFiles(files: lib.map { [ignore: .contents($0)] } ?? [:])
            ])
        ]
    )
}

struct IgnoreFilesMergeTests {
    @Test func mergeReportsChangedDirectories() {
        var tree = branch("a\n", nil)
        let same = tree.merge(branch("a\n", nil))
        let changed = tree.merge(branch("b\n", "c\n"))
        let removed = tree.merge(branch(nil, "c\n"))

        #expect(same == [])
        #expect(changed == ["", "src/lib"])
        #expect(removed == [""])
        #expect(tree == branch(nil, "c\n"))
    }

    @Test func newDirectoryIsNotAChange() {
        var tree = IgnoreFiles()
        let changed = tree.merge(
            IgnoreFiles(children: ["src": IgnoreFiles(files: [ignore: .contents("a\n")])])
        )

        #expect(changed == [])
        #expect(tree.children["src"]?.files == [ignore: .contents("a\n")])
    }

    @Test func remoteFileKeepsKnownContents() {
        var tree = IgnoreFiles(files: [ignore: .contents("a\n")])
        let changed = tree.merge(IgnoreFiles(files: [ignore: .remote]))

        #expect(changed == [])
        #expect(tree.files == [ignore: .contents("a\n")])
    }

    @Test func remoteFileWithoutKnownContentsIsDropped() {
        var tree = IgnoreFiles()
        let changed = tree.merge(
            IgnoreFiles(
                files: [ignore: .remote],
                children: ["src": IgnoreFiles(files: [ignore: .remote])]
            )
        )

        #expect(changed == [])
        #expect(tree == IgnoreFiles(children: ["src": IgnoreFiles()]))
    }

    @Test func mergeLeavesSiblingsAlone() {
        let srcs = IgnoreFiles(files: [ignore: .contents("*.o\n")])
        var tree = IgnoreFiles(children: ["srcs": srcs])
        _ = tree.merge(IgnoreFiles(children: ["src": IgnoreFiles()]))

        #expect(tree.children["srcs"] == srcs)
    }

    @Test func knownDropsRemoteFiles() {
        let tree = IgnoreFiles(
            files: [ignore: .remote, ".gitignore": .contents("a\n")],
            children: ["src": IgnoreFiles(files: [ignore: .remote])]
        )

        #expect(
            tree.known
                == IgnoreFiles(
                    files: [".gitignore": .contents("a\n")],
                    children: ["src": IgnoreFiles()]
                )
        )
    }

    @Test func branchInitNestsEachLevel() {
        let tree = IgnoreFiles(
            branch: ["src", "lib"],
            files: [[ignore: .contents("a\n")], [:], [ignore: .contents("b\n")]]
        )
        #expect(tree == branch("a\n", "b\n"))
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
