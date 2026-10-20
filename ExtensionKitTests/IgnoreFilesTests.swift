import Common
import Foundation
import Testing

@testable import CoreKit
@testable import ExtensionKit

struct IgnoreFilesTests {
    @Test func readsEachLevelFromRootToDirectory() throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: ".sshadowignore", contents: "build/\n")
        try sandbox.createFile(at: "src/lib/.sshadowignore", contents: "*.log\n")

        let files = IgnoreFiles.read(
            [".sshadowignore"],
            from: sandbox.mount,
            to: sandbox.mount.appending(path: "src/lib")
        )

        #expect(
            files
                == IgnoreFiles(
                    files: [".sshadowignore": .contents("build/\n")],
                    children: [
                        "src": IgnoreFiles(children: [
                            "lib": IgnoreFiles(files: [".sshadowignore": .contents("*.log\n")])
                        ])
                    ]
                )
        )
    }

    @Test func readsOnlyTheGivenFilenames() throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(at: ".gitignore", contents: "a\n")
        try sandbox.createFile(at: ".sshadowignore", contents: "b\n")
        try sandbox.createFile(at: ".otherignore", contents: "c\n")

        let files = IgnoreFiles.read(
            [".gitignore", ".sshadowignore"],
            from: sandbox.mount,
            to: sandbox.mount
        )

        #expect(
            files
                == IgnoreFiles(files: [
                    ".gitignore": .contents("a\n"), ".sshadowignore": .contents("b\n"),
                ])
        )
    }

    @Test func leavesUnreadableFilesToTheRemote() throws {
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: ".sshadowignore")

        let files = IgnoreFiles.read(
            [".sshadowignore"],
            from: sandbox.mount,
            to: sandbox.mount
        )

        #expect(files == IgnoreFiles(files: [".sshadowignore": .remote]))
    }

    @Test func directoryOutsideRootReadsNothing() {
        let sandbox = TestSandbox()

        let files = IgnoreFiles.read(
            [".sshadowignore"],
            from: sandbox.mount,
            to: sandbox.shared
        )

        #expect(files == nil)
    }
}
