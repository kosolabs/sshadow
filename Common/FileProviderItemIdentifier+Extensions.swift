import FileProvider

extension NSFileProviderItemIdentifier {
    public static let sshadowContainer = NSFileProviderItemIdentifier(
        "NSFileProviderSSHadowContainerItemIdentifier"
    )

    public var desc: String {
        switch self {
        case .rootContainer:
            return ".rootContainer"
        case .workingSet:
            return ".workingSet"
        case .trashContainer:
            return ".trashContainer"
        case .sshadowContainer:
            return ".sshadowContainer"
        default:
            return rawValue
        }
    }
}
