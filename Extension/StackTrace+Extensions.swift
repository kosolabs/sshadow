import Common
import FileProvider

private let logger = Logger(category: "StackTrace")

extension StackTrace {
    func log(_ logger: Logger = logger, error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSFileProviderErrorDomain
            || nsError.domain == NSCocoaErrorDomain
        {
            logger.debug("Error at \(caller): \(error)")
        } else {
            logger.fault("Unmapped error at \(caller): \(error)\n\(description)")
        }
    }
}
