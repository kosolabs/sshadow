import Common
import FileProvider
import OSLog
import SwiftLibSSH

let logger = getLogger(category: "ErrorMapper")

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

    logger.error("Remapping error: \(error, privacy: .public)")
    return NSFileProviderError(
        .cannotSynchronize,
        userInfo: [
            NSUnderlyingErrorKey: error,
            NSLocalizedDescriptionKey:
                "An error occurred while communicating with the server: \(error.localizedDescription)",
        ]
    )
}
