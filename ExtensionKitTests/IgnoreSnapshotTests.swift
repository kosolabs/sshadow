import Common
import Foundation
import TestKit
import Testing

@testable import CoreKit
@testable import ExtensionKit

private let date = Date(timeIntervalSince1970: 1_767_225_600)

private func text(
    _ contents: String,
    named name: String = ".sshadowignore"
) -> IgnoreFile {
    IgnoreFile(
        name: name,
        content: .loaded(
            contents,
            version: IgnoreFile.Version(
                modifyTime: date,
                size: UInt64(contents.utf8.count)
            )
        )
    )
}

struct IgnoreSnapshotTests {
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

        let snapshot = IgnoreSnapshot.read(
            [".sshadowignore"],
            from: sandbox.url(in: .local),
            to: sandbox.url(for: "src/lib", in: .local)
        )

        #expect(
            snapshot
                == [
                    IgnoreFolder(path: "", files: [text("build/\n")]),
                    IgnoreFolder(path: "src", files: []),
                    IgnoreFolder(path: "src/lib", files: [text("*.log\n")]),
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

        let snapshot = IgnoreSnapshot.read(
            [".gitignore", ".sshadowignore"],
            from: sandbox.url(in: .local),
            to: sandbox.url(in: .local)
        )

        #expect(
            snapshot
                == [
                    IgnoreFolder(
                        path: "",
                        files: [
                            text("a\n", named: ".gitignore"),
                            text("b\n"),
                        ]
                    )
                ]
        )
    }

    @Test func marksUnreadableFilesUnresolved() throws {
        let sandbox = TestSandbox()
        try sandbox.createFolder(at: ".sshadowignore", in: .local)

        let snapshot = IgnoreSnapshot.read(
            [".sshadowignore"],
            from: sandbox.url(in: .local),
            to: sandbox.url(in: .local)
        )

        #expect(
            snapshot
                == [
                    IgnoreFolder(
                        path: "",
                        files: [
                            IgnoreFile(
                                name: ".sshadowignore",
                                content: .unresolved
                            )
                        ]
                    )
                ]
        )
    }

    @Test func directoryOutsideRootReadsNothing() {
        let sandbox = TestSandbox()

        let snapshot = IgnoreSnapshot.read(
            [".sshadowignore"],
            from: sandbox.url(in: .local),
            to: sandbox.url(in: .group)
        )

        #expect(snapshot == nil)
    }
}
