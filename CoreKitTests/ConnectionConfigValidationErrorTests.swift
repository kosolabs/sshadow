import Common
import SwiftLibSSH
import Testing

@testable import CoreKit

@Suite struct ConnectionConfigValidationErrorTests {
    @Test(
        arguments: [
            (SSHKeyError.unreadable, ConnectionConfig.ValidationError.privateKeyUnreadable),
            (SSHKeyError.passphraseRequired, .passphraseRequired),
            (SSHKeyError.invalid, .privateKeyInvalid),
        ]
    )
    func mapsKeyError(
        _ keyError: SSHKeyError,
        _ expected: ConnectionConfig.ValidationError
    ) {
        #expect(ConnectionConfig.ValidationError(keyError) == expected)
    }
}
