import Foundation
import Testing

@testable import CoreKit

private let installed = URL(
    filePath: "/Applications/SSHadow.app/Contents/PlugIns/Extension.appex"
)

struct XPCBrokerTests {
    @Test func ownExtensionIsNotAMismatch() {
        #expect(extensionMismatch(connected: installed, expected: installed) == nil)
    }

    @Test func ownExtensionAsDirectoryIsNotAMismatch() {
        let connected = URL(filePath: installed.path(), directoryHint: .isDirectory)

        #expect(extensionMismatch(connected: connected, expected: installed) == nil)
    }

    @Test func unknownExtensionIsNotAMismatch() {
        #expect(extensionMismatch(connected: nil, expected: installed) == nil)
    }

    @Test func extensionFromAnotherCopyIsAMismatch() {
        let connected = URL(
            filePath: "/Volumes/SSHadow/SSHadow.app/Contents/PlugIns/Extension.appex"
        )

        #expect(
            extensionMismatch(connected: connected, expected: installed)
                == "connected /Volumes/SSHadow/SSHadow.app/Contents/PlugIns/Extension.appex, "
                + "expected /Applications/SSHadow.app/Contents/PlugIns/Extension.appex"
        )
    }
}
