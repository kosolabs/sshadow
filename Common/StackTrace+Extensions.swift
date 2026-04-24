import FileProvider

extension StackTrace {
    public func log(
        _ logger: Logger = Logger(category: "StackTrace"),
        error: Error
    ) {
        let nsError = error as NSError
        if nsError.domain != NSFileProviderErrorDomain
            && nsError.domain != NSCocoaErrorDomain
        {
            logger.fault(
                "Unmapped error at \(caller): \(error)\n\(description)"
            )
        }
    }
}
