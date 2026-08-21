import FileProvider

extension NSFileProviderItemIdentifier: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .rootContainer:
            return ".rootContainer"
        case .workingSet:
            return ".workingSet"
        case .trashContainer:
            return ".trashContainer"
        default:
            return rawValue
        }
    }
}
