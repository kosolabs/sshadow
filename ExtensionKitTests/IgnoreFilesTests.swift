import Common
import Foundation
import TestKit
import Testing

@testable import CoreKit
@testable import ExtensionKit

private let date = Date(timeIntervalSince1970: 1_767_225_600)

struct IgnoreFilesTests {
    @Test func readsEachLevelFromRootToDirectory() throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(
            at: ".sshadowignore",
            contents: "build/\n",
            modifyDate: date
        )
        try sandbox.createFile(
            at: "src/lib/.sshadowignore",
            contents: "*.log\n",
            modifyDate: date
        )

        let files = IgnoreFiles.read(
            [".sshadowignore"],
            from: sandbox.remote,
            to: sandbox.remote.appending(path: "src/lib")
        )

        #expect(
            files
                == IgnoreFiles(
                    files: [".sshadowignore": .contents("build/\n")],
                    children: [
                        "src": IgnoreFiles(children: [
                            "lib": IgnoreFiles(files: [
                                ".sshadowignore": .contents("*.log\n")
                            ])
                        ])
                    ]
                )
        )
    }

    @Test func readsOnlyTheGivenFilenames() throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(
            at: ".gitignore",
            contents: "a\n",
            modifyDate: date
        )
        try sandbox.createFile(
            at: ".sshadowignore",
            contents: "b\n",
            modifyDate: date
        )
        try sandbox.createFile(
            at: ".otherignore",
            contents: "c\n",
            modifyDate: date
        )

        let files = IgnoreFiles.read(
            [".gitignore", ".sshadowignore"],
            from: sandbox.remote,
            to: sandbox.remote
        )

        #expect(
            files
                == IgnoreFiles(files: [
                    ".gitignore": .contents("a\n"),
                    ".sshadowignore": .contents("b\n"),
                ])
        )
    }

    @Test func leavesUnreadableFilesToTheRemote() throws {
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: ".sshadowignore")

        let files = IgnoreFiles.read(
            [".sshadowignore"],
            from: sandbox.remote,
            to: sandbox.remote
        )

        #expect(files == IgnoreFiles(files: [".sshadowignore": .remote]))
    }

    @Test func directoryOutsideRootReadsNothing() {
        let sandbox = TestSandbox()

        let files = IgnoreFiles.read(
            [".sshadowignore"],
            from: sandbox.remote,
            to: sandbox.group
        )

        #expect(files == nil)
    }
}
