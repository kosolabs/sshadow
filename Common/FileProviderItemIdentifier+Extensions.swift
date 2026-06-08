import FileProvider

extension NSFileProviderItemIdentifier {
    public var desc: String {
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
