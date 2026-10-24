public enum IgnoreFile: Message, PrettyDescribable {
    case contents(String)
    case unresolved
}

/// The ignore files in each folder from the root down to a parent, root first.
public typealias IgnoreLevels = [[String: IgnoreFile]]
