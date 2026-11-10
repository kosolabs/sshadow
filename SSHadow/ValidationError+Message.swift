import CoreKit

extension ConnectionConfig.ValidationError {
    var message: String {
        switch self {
        case .passwordMissing:
            "Password is required."
        case .privateKeyMissing:
            "Private key is required."
        case .privateKeyUnreadable:
            "The selected file isn't a readable private key."
        case .passphraseRequired:
            "This private key requires a passphrase."
        case .privateKeyInvalid:
            "Private key is invalid or the passphrase is incorrect."
        case .ignoreFilenameInvalid:
            "Ignore file names can't be empty or contain slashes."
        case .hostKeyUnknown:
            "The server's host key hasn't been checked yet."
        }
    }
}
