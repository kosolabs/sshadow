import Common
import SwiftRussh
import Testing

@testable import CoreKit

@Suite struct ConnectionConfigValidationErrorTests {
    @Test(
        arguments: [
            (
                SSHError.PrivateKeyFailure.unreadable,
                ConnectionConfig.ValidationError.privateKeyUnreadable
            ),
            (SSHError.PrivateKeyFailure.passphraseRequired, .passphraseRequired),
            (SSHError.PrivateKeyFailure.invalid, .privateKeyInvalid),
        ]
    )
    func mapsPrivateKeyFailure(
        _ failure: SSHError.PrivateKeyFailure,
        _ expected: ConnectionConfig.ValidationError
    ) {
        #expect(ConnectionConfig.ValidationError(failure) == expected)
    }
}
