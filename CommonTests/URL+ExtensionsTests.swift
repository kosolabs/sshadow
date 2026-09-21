import Foundation
import Testing

@testable import Common

private let parent = "/Users/home/Library/CloudStorage"

private func cloudStorageUrl(_ name: String) -> URL {
    URL(filePath: "\(parent)/\(name)")
}

private let awkwardNames = [
    "SSHadow-MySSHServer",
    "SSHadow-Dev&Test",
    "SSHadow-User'sServer",
    "SSHadow-user@host.com:2222:mnt:sshadow",
    "SSHadow-Dev $HOME (x)",
    "SSHadow-back\\slash",
    "SSHadow-semi;colon",
    "SSHadow-star*glob?",
    "SSHadow-back`tick`",
    "SSHadow-café",
]

private func shellExpansion(of escaped: String) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", "printf '%s' \(escaped)"]

    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return String(data: data, encoding: .utf8) ?? ""
}

struct ShellEscapedPathTests {
    @Test func inertPathIsLeftAlone() {
        let url = cloudStorageUrl("SSHadow-MySSHServer")
        #expect(url.shellEscapedPath == "\(parent)/SSHadow-MySSHServer")
    }

    @Test func sanitizedUnnamedProfilePathIsLeftAlone() {
        let url = cloudStorageUrl("SSHadow-user@host.com:2222:mnt:sshadow")
        #expect(
            url.shellEscapedPath
                == "\(parent)/SSHadow-user@host.com:2222:mnt:sshadow"
        )
    }
    
    @Test func ampersandIsEscaped() {
        let url = cloudStorageUrl("Dev&Test")
        #expect(url.shellEscapedPath == "\(parent)/Dev\\&Test")
    }
    
    @Test func dollarSignIsEscaped() {
        let url = cloudStorageUrl("Dev$Test")
        #expect(url.shellEscapedPath == "\(parent)/Dev\\$Test")
    }
    
    @Test func spaceIsEscaped() {
        let url = cloudStorageUrl("Dev Test")
        #expect(url.shellEscapedPath == "\(parent)/Dev\\ Test")
    }
    
    @Test func singleQuoteIsEscaped() {
        let url = cloudStorageUrl("Dev'Test")
        #expect(url.shellEscapedPath == "\(parent)/Dev\\'Test")
    }
    
    @Test func backslashIsEscaped() {
        let url = cloudStorageUrl("Dev\\Test")
        #expect(url.shellEscapedPath == "\(parent)/Dev\\\\Test")
    }

    @Test func nonAsciiLettersAreNotEscaped() {
        let url = cloudStorageUrl("café")
        #expect(url.shellEscapedPath == "\(parent)/café")
    }

    @Test func trailingSlashIsPreserved() {
        let url = URL(filePath: "\(parent)/dir/")
        #expect(url.shellEscapedPath == "\(parent)/dir/")
    }

    @Test func percentIsNotTreatedAsEncoding() {
        let url = cloudStorageUrl("Dev%20Test")
        #expect(url.shellEscapedPath == "\(parent)/Dev%20Test")
    }

    @Test(arguments: awkwardNames)
    func roundTripsThroughShell(name: String) throws {
        let url = cloudStorageUrl(name)
        #expect(
            try shellExpansion(of: url.shellEscapedPath)
                == url.path(percentEncoded: false)
        )
    }
}
