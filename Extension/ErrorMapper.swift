import Common
import FileProvider
import SwiftLibSSH

let logger = Logger(category: "ErrorMapper")

func remap(error: Error) -> Error {
    let nsError = error as NSError
    if nsError.domain == NSFileProviderErrorDomain
        || nsError.domain == NSCocoaErrorDomain
    {
        return error
    }

    if let sshError = error as? SSHError {
        if case .sftpError(let sftpError, _) = sshError,
            sftpError == .noSuchFile
        {
            return NSFileProviderError(.noSuchItem)
        }
        if case .connectionFailed = sshError {
            return NSFileProviderError(.serverUnreachable)
        }
        if case .authenticationFailed = sshError {
            return NSFileProviderError(.notAuthenticated)
        }
    }

    logger.fault("Remapping error: \(error)")
    return NSFileProviderError(
        .cannotSynchronize,
        userInfo: [
            NSUnderlyingErrorKey: error,
            NSLocalizedDescriptionKey:
                "An error occurred while communicating with the server: \(error.localizedDescription)",
        ]
    )
}
