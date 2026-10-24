import Common
import Foundation
import TestKit
import Testing

@testable import CoreKit
@testable import ExtensionKit

private let date = Date(timeIntervalSince1970: 1_767_225_600)

struct IgnoreLevelsTests {
    @Test func readsEachLevelFromRootToDirectory() throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(
            at: ".sshadowignore",
            in: .local,
            contents: "build/\n",
            modifyDate: date
        )
        try sandbox.createFile(
            at: "src/lib/.sshadowignore",
            in: .local,
            contents: "*.log\n",
            modifyDate: date
        )

        let files = IgnoreLevels.read(
            [".sshadowignore"],
            from: sandbox.url(in: .local),
            to: sandbox.url(for: "src/lib", in: .local)
        )

        #expect(
            files == [
                [".sshadowignore": .contents("build/\n")],
                [:],
                [".sshadowignore": .contents("*.log\n")],
            ]
        )
    }

    @Test func readsOnlyTheGivenFilenames() throws {
        let sandbox = TestSandbox()
        try sandbox.createFile(
            at: ".gitignore",
            in: .local,
            contents: "a\n",
            modifyDate: date
        )
        try sandbox.createFile(
            at: ".sshadowignore",
            in: .local,
            contents: "b\n",
            modifyDate: date
        )
        try sandbox.createFile(
            at: ".otherignore",
            in: .local,
            contents: "c\n",
            modifyDate: date
        )

        let files = IgnoreLevels.read(
            [".gitignore", ".sshadowignore"],
            from: sandbox.url(in: .local),
            to: sandbox.url(in: .local)
        )

        #expect(
            files
                == [[
                    ".gitignore": .contents("a\n"),
                    ".sshadowignore": .contents("b\n"),
                ]]
        )
    }

    @Test func marksUnreadableFilesUnresolved() throws {
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: ".sshadowignore", in: .local)

        let files = IgnoreLevels.read(
            [".sshadowignore"],
            from: sandbox.url(in: .local),
            to: sandbox.url(in: .local)
        )

        #expect(files == [[".sshadowignore": .unresolved]])
    }

    @Test func directoryOutsideRootReadsNothing() {
        let sandbox = TestSandbox()

        let files = IgnoreLevels.read(
            [".sshadowignore"],
            from: sandbox.url(in: .local),
            to: sandbox.url(in: .group)
        )

        #expect(files == nil)
    }
}
