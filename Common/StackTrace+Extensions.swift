import FileProvider

extension StackTrace {
    public func log(
        _ logger: Logger = Logger(category: "StackTrace"),
        error: AgentError
    ) {
        if error.isUnknown {
            logger.fault(
                "Unmapped error at \(caller): \(error)\n\(description)"
            )
        }
    }
}
