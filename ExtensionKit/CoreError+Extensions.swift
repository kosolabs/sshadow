import Common
import FileProvider

extension CoreError {
    public var asNSError: any Error {
        switch self {
        case .serviceUnreachable,
            .remotePathNotFound,
            .unexpectedResponse,
            .serverUnreachable:
            NSFileProviderError(.serverUnreachable)
        case .profileNotFound, .notAuthenticated:
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
