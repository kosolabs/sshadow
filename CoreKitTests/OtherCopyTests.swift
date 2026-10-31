import Foundation
import Testing

@testable import CoreKit

private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
private let installed = URL(filePath: "/Applications/SSHadow.app")
private let translocated = URL(
    filePath:
        "/private/var/folders/x_/abc/T/AppTranslocation/1234/d/SSHadow.app"
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
            filePath:
                "/Users/me/Downloads/SSHadow.app/Contents/PlugIns/Extension.appex/",
            directoryHint: .isDirectory
        )

        #expect(
            interferenceDetail(
                other: appex.containingApp,
                own: installed,
                home: home
            )
                == "The copy at ~/Downloads/SSHadow.app is syncing this folder "
                + "instead of this one at /Applications/SSHadow.app."
        )
    }

    @Test func fixDescribesTheOtherCopyAndHowToUnregisterIt() {
        let appex = URL(
            filePath:
                "/Users/me/Downloads/SSHadow.app/Contents/PlugIns/Extension.appex/",
            directoryHint: .isDirectory
        )

        let fix = UnreachableFix(otherExtension: appex, home: home)

        #expect(fix.otherCopy == "The copy at ~/Downloads/SSHadow.app")
        #expect(
            fix.otherApp == URL(filePath: "/Users/me/Downloads/SSHadow.app")
        )
        #expect(
            fix.command
                == "pluginkit -r /Users/me/Downloads/SSHadow.app/Contents/PlugIns/Extension.appex\n"
                + "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
                + "LaunchServices.framework/Support/lsregister -u /Users/me/Downloads/SSHadow.app\n"
                + "killall fileproviderd"
        )
    }

    @Test func fixForTranslocatedCopyHidesItsLocation() {
        let fix = UnreachableFix(
            otherExtension: translocated.appending(
                path: "Contents/PlugIns/Extension.appex"
            ),
            home: home
        )

        #expect(fix.otherCopy == "A copy opened from Downloads or a disk image")
        #expect(fix.otherApp == nil)
        #expect(
            fix.command.contains(
                "-u \(translocated.path(percentEncoded: false))"
            )
        )
    }

    @Test func fixEscapesPathsInTheCommand() {
        let fix = UnreachableFix(
            otherExtension: URL(
                filePath:
                    "/Volumes/SSHadow Beta/SSHadow.app/Contents/PlugIns/Extension.appex"
            ),
            home: home
        )

        #expect(
            fix.command.hasPrefix(
                "pluginkit -r /Volumes/SSHadow\\ Beta/SSHadow.app/Contents/PlugIns/Extension.appex\n"
            )
        )
        #expect(
            fix.command.contains(" -u /Volumes/SSHadow\\ Beta/SSHadow.app\n")
        )
    }

    @Test func fixWithoutAnotherCopyOnlyRestartsSync() {
        let fix = UnreachableFix(otherExtension: nil, home: home)

        #expect(fix.otherCopy == nil)
        #expect(fix.otherApp == nil)
        #expect(fix.command == "killall fileproviderd")
    }
}
