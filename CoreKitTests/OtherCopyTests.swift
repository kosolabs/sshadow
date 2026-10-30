import Foundation
import Testing

@testable import CoreKit

private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
private let installed = URL(filePath: "/Applications/SSHadow.app")
private let translocated = URL(
    filePath: "/private/var/folders/x_/abc/T/AppTranslocation/1234/d/SSHadow.app"
)

struct OtherCopyTests {
    @Test func describesCopiesByLocation() {
        let other = URL(filePath: "/Volumes/SSHadow/SSHadow.app")

        #expect(
            interferenceDetail(other: other, own: installed, home: home)
                == "The copy at /Volumes/SSHadow/SSHadow.app is syncing this folder "
                + "instead of this one at /Applications/SSHadow.app."
        )
    }

    @Test func shortensTheHomeFolder() {
        let other = URL(filePath: "/Users/me/Downloads/SSHadow.app")

        #expect(
            interferenceDetail(other: other, own: installed, home: home)
                == "The copy at ~/Downloads/SSHadow.app is syncing this folder "
                + "instead of this one at /Applications/SSHadow.app."
        )
    }

    @Test func leavesSimilarlyNamedFoldersAlone() {
        let other = URL(filePath: "/Users/mel/SSHadow.app")

        #expect(
            interferenceDetail(other: other, own: installed, home: home)
                == "The copy at /Users/mel/SSHadow.app is syncing this folder "
                + "instead of this one at /Applications/SSHadow.app."
        )
    }

    @Test func describesTranslocatedOtherCopyWithoutItsPath() {
        #expect(
            interferenceDetail(other: translocated, own: installed, home: home)
                == "A copy opened from Downloads or a disk image is syncing this "
                + "folder instead of this one at /Applications/SSHadow.app."
        )
    }

    @Test func describesTranslocatedOwnCopyWithoutItsPath() {
        let other = URL(filePath: "/Applications/SSHadow.app")

        #expect(
            interferenceDetail(other: other, own: translocated, home: home)
                == "The copy at /Applications/SSHadow.app is syncing this folder "
                + "instead of this one."
        )
    }

    @Test func findsTheAppContainingAnExtension() {
        let appex = URL(
            filePath: "/Users/me/Downloads/SSHadow.app/Contents/PlugIns/Extension.appex/",
            directoryHint: .isDirectory
        )

        #expect(
            interferenceDetail(other: appex.containingApp, own: installed, home: home)
                == "The copy at ~/Downloads/SSHadow.app is syncing this folder "
                + "instead of this one at /Applications/SSHadow.app."
        )
    }
}
