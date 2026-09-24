import Foundation
import Testing

@testable import Common

struct FileTreeTests {
    @Test func walksFoldersBeforeTheirChildren() throws {
        let sandbox = TestSandbox()
        let root = try sandbox.createFolder(at: "pkg", relativeTo: .shared)
        try sandbox.createFile(
            at: "pkg/Contents/Resources/data.bin",
            relativeTo: .shared,
            contents: "data"
        )
        try sandbox.createFile(
            at: "pkg/Info.plist",
            relativeTo: .shared,
            contents: "plist"
        )

        let tree = try FileTree(root: root)

        #expect(
            tree.entries.map(\.path) == [
                "Contents",
                "Contents/Resources",
                "Contents/Resources/data.bin",
                "Info.plist",
            ]
        )
        #expect(tree.entries.map(\.isFolder) == [true, true, false, false])
        #expect(tree.totalSize == 9)
    }

    @Test func recordsFileSizesFlagsAndParents() throws {
        let sandbox = TestSandbox()
        let root = try sandbox.createFolder(at: "pkg", relativeTo: .shared)
        try sandbox.createFile(
            at: "pkg/bin/tool",
            relativeTo: .shared,
            contents: "executable",
            permissions: 0o755
        )

        let tree = try FileTree(root: root)
        let tool = try #require(tree.entries.last)

        #expect(tool.name == "tool")
        #expect(tool.parent == "bin")
        #expect(tool.path == "bin/tool")
        #expect(tool.size == 10)
        #expect(tool.flags == .all)
    }

    @Test func recordsSymlinksWithoutFollowingThem() throws {
        let sandbox = TestSandbox()
        let root = try sandbox.createFolder(at: "pkg", relativeTo: .shared)
        try sandbox.createFile(
            at: "pkg/Versions/A/lib",
            relativeTo: .shared,
            contents: "lib"
        )
        try sandbox.createSymlink(
            at: "pkg/Versions/Current",
            relativeTo: .shared,
            target: "A"
        )
        try sandbox.createSymlink(
            at: "pkg/broken",
            relativeTo: .shared,
            target: "nowhere"
        )

        let tree = try FileTree(root: root)

        // A symlink to a folder is a leaf: its target is recorded, and the
        // walk does not descend through it.
        #expect(
            tree.entries.map(\.path) == [
                "Versions",
                "Versions/A",
                "Versions/A/lib",
                "Versions/Current",
                "broken",
            ]
        )

        let targets = tree.entries.compactMap { entry -> String? in
            if case .symlink(let target) = entry.kind { target } else { nil }
        }
        #expect(targets == ["A", "nowhere"])
    }

    @Test func expectedNamesCoversEveryFolder() throws {
        let sandbox = TestSandbox()
        let root = try sandbox.createFolder(at: "pkg", relativeTo: .shared)
        try sandbox.createFile(
            at: "pkg/Contents/Info.plist",
            relativeTo: .shared,
            contents: "plist"
        )
        try sandbox.createFolder(at: "pkg/Empty", relativeTo: .shared)

        let tree = try FileTree(root: root)

        #expect(
            tree.expectedNames == [
                "": ["Contents", "Empty"],
                "Contents": ["Info.plist"],
                "Empty": [],
            ]
        )
    }

    @Test func emptyFolderHasNoEntries() throws {
        let sandbox = TestSandbox()
        let root = try sandbox.createFolder(at: "pkg", relativeTo: .shared)

        let tree = try FileTree(root: root)

        #expect(tree.entries.isEmpty)
        #expect(tree.totalSize == 0)
        #expect(tree.expectedNames == ["": []])
    }
}
