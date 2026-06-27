import Common
import FileProvider

extension AgentError {
    public var asNSError: any Error {
        switch self {
        case .agentUnreachable,
            .unknownHost,
            .connectionRefused,
            .connectionTimedOut,
            .remotePathNotFound,
            .remotePathNotDirectory,
            .unexpectedResponse:
            NSFileProviderError(.serverUnreachable)
        case .profileNotFound, .invalidPrivateKey, .passwordAuthFailed:
            NSFileProviderError(.notAuthenticated)
        case .permissionDenied:
            CocoaError(.fileWriteNoPermission)
        case .userCancelled:
            CocoaError(.userCancelled)
        case .itemNotFound(let itemId?):
            NSError.fileProviderErrorForNonExistentItem(
                withIdentifier: NSFileProviderItemIdentifier(itemId)
            )
        case .itemNotFound(nil):
            NSFileProviderError(.noSuchItem)
        case .filenameCollision:
            NSFileProviderError(.filenameCollision)
        case .unknown(let domain, let code, let message):
            NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
