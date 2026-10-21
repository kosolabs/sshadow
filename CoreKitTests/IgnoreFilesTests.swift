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

struct IgnoreFilesBranchTests {
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

    @Test func levelsListParentsBeforeChildren() {
        let tree = branch(text("a\n"), text("b\n"))
        let levels = tree.levels.map(\.dir)
        #expect(levels == ["", "src", "src/lib"])
        #expect(tree.levels.last?.files == [ignore: text("b\n")])
    }
}
