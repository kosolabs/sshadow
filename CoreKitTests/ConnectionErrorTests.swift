import Common
import Foundation
import SwiftLibSSH
import Testing

@testable import CoreKit

@Suite struct ConnectionErrorTests {
    @Test func mapsUnknownHost() {
        let error = ConnectionError(
            from: SSHError.connectionFailed(
                message: "Failed to resolve hostname example.invalid"
            )
        )
        #expect(error == .unknownHost)
    }

    @Test(
        arguments: [
            "Connection refused",
            "Socket error",
            "Bad file descriptor",
        ]
    )
    func mapsConnectionRefused(_ message: String) {
        let error = ConnectionError(
            from: SSHError.connectionFailed(message: message)
        )
        #expect(error == .connectionRefused)
    }

    @Test func mapsConnectionTimedOut() {
        let error = ConnectionError(
            from: SSHError.connectionFailed(message: "Timeout connecting")
        )
        #expect(error == .connectionTimedOut)
    }

    @Test func mapsInvalidPrivateKey() {
        let error = ConnectionError(
            from: SSHError.authenticationFailed(
                message: "Failed to import private key"
            )
        )
        #expect(error == .invalidPrivateKey)
    }

    @Test func mapsAuthenticationFailed() {
        let error = ConnectionError(
            from: SSHError.authenticationFailed(message: "Access denied")
        )
        #expect(error == .authenticationFailed)
    }

    @Test func mapsRemotePathNotFound() {
        let error = ConnectionError(
            from: SSHError.sftpError(.noSuchFile, message: "no such file")
        )
        #expect(error == .remotePathNotFound)
    }

    @Test func mapsUnrecognizedSSHErrorToUnknown() {
        let error = ConnectionError(
            from: SSHError.connectionFailed(message: "something unexpected")
        )
        guard case .unknown = error else {
            Issue.record("Expected .unknown, got \(error)")
            return
        }
    }

    @Test func passesThroughExistingConnectionError() {
        let error = ConnectionError(
            from: ConnectionError.remotePathNotDirectory
        )
        #expect(error == .remotePathNotDirectory)
    }

    @Test func mapsArbitraryErrorToUnknown() {
        let nsError = NSError(
            domain: "TestDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "boom"]
        )
        let error = ConnectionError(from: nsError)
        #expect(
            error == .unknown(domain: "TestDomain", code: 42, message: "boom")
        )
    }
}
