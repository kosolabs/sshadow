import FileProvider

public struct Ref: PrettyDescribable {
    public enum Anchor {
        case item(id: String)
        case parent(id: String)
    }

    private let path: String?
    private let anchor: Anchor

    public init(path: String?, anchor: Anchor) {
        self.path = path
        self.anchor = anchor
    }

    private var itemId: NSFileProviderItemIdentifier? {
        guard case .item(let id) = anchor else { return nil }
        return NSFileProviderItemIdentifier(id)
    }

    public var display: String {
        switch itemId {
        case .rootContainer: "Root"
        case .trashContainer: "Trash"
        default: path.map { "\"\($0)\"" } ?? "(deleted)"
        }
    }
}
