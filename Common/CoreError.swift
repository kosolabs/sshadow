import FileProvider
import Foundation

private let logger = Logger(category: "CoreError")

public enum CoreError: Message, PrettyDescribable, Error {
    case serviceUnreachable
    case profileNotFound
    case userCancelled
    case permissionDenied
    case itemNotFound(String?)
    case filenameCollision
    case serverUnreachable
    case notAuthenticated
    case remotePathNotFound
    case featureUnsupported
    case ignored
    case cannotSynchronize
    case unknown(domain: String, code: Int, message: String)

    public static var itemNotFound: CoreError {
        .itemNotFound(nil)
    }

    public static func itemNotFound(
        _ id: NSFileProviderItemIdentifier
    ) -> CoreError {
        .itemNotFound(id.rawValue)
    }

    public init(from error: any Error) {
        if let coreError = error as? CoreError {
            self = coreError
            return
        }
        if error is CancellationError {
            self = .userCancelled
            return
        }
        if let error = error as? CocoaError,
            [.xpcConnectionInterrupted, .xpcConnectionInvalid].contains(
                error.code
            )
        {
            self = .serviceUnreachable
            return
        }
        logger.error("Unhandled error type: \(error)")
        let nsError = error as NSError
        self = .unknown(
            domain: nsError.domain,
            code: nsError.code,
            message: nsError.localizedDescription
        )
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}
