import Common
import Foundation
import SwiftRussh
import Testing

@testable import CoreKit

@Suite struct ConnectionErrorTests {
    @Test(
        arguments: zip(
            [
                SSHError.ConnectionFailure.unknownHost, .refused, .timedOut,
                .unreachable, .lost,
            ],
            [
                ConnectionError.unknownHost, .connectionRefused,
                .connectionTimedOut, .hostUnreachable, .connectionLost,
            ]
        )
    )
    func mapsConnectionFailureReasons(
        _ failure: SSHError.ConnectionFailure,
        _ expected: ConnectionError
    ) {
        let error = ConnectionError(
            from: SSHError.connectionFailed(failure, message: "detail")
        )
        #expect(error == expected)
    }

    @Test func mapsHostKeyMismatchToTheNewKey() {
        let error = ConnectionError(
            from: SSHError.hostKeyMismatch(
                expected: otherHostKey,
                actual: unrelatedHostKey,
                message: "mismatch"
            )
        )
        #expect(error == .hostKeyChanged(unrelatedHostKey))
    }

    @Test func changedHostKeyDetailNamesTheNewFingerprint() {
        let error = ConnectionError.hostKeyChanged(unrelatedHostKey)
        #expect(
            error.detail
                == "Host key changed; the server now presents \(unrelatedHostKey.fingerprint)"
        )
    }

    @Test func otherErrorDetailsAreTheirMessage() {
        #expect(ConnectionError.connectionRefused.detail == "Connection refused")
    }

    @Test(
        arguments: [
            SSHError.PrivateKeyFailure.unreadable, .passphraseRequired, .invalid,
        ]
    )
    func mapsPrivateKeyFailuresToInvalidPrivateKey(
        _ failure: SSHError.PrivateKeyFailure
    ) {
        let error = ConnectionError(
            from: SSHError.privateKey(failure, message: "detail")
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
            from: SSHError.sftp(.noSuchFile, message: "no such file")
        )
        #expect(error == .remotePathNotFound)
    }

    @Test func mapsUnrecognizedSSHErrorToUnknown() {
        let error = ConnectionError(
            from: SSHError.connectionFailed(
                .other,
                message: "something unexpected"
            )
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
