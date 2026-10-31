import Foundation
import Testing

@testable import CoreKit

private let installed = URL(
    filePath: "/Applications/SSHadow.app/Contents/PlugIns/Extension.appex"
)

struct XPCBrokerTests {
    @Test func ownExtensionIsNotWrong() {
        #expect(
            wrongExtension(connected: installed, expected: installed) == nil
        )
    }

    @Test func ownExtensionAsDirectoryIsNotWrong() {
        let connected = URL(
            filePath: installed.path(),
            directoryHint: .isDirectory
        )

        #expect(
            wrongExtension(connected: connected, expected: installed) == nil
        )
    }

    @Test func unknownExtensionIsNotWrong() {
        #expect(wrongExtension(connected: nil, expected: installed) == nil)
    }

    @Test func extensionFromAnotherCopyIsWrong() {
        let connected = URL(
            filePath:
                "/Volumes/SSHadow/SSHadow.app/Contents/PlugIns/Extension.appex"
        )

        #expect(
            wrongExtension(connected: connected, expected: installed)
                == connected
        )
    }
}
