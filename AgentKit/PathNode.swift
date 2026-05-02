import FileProvider
import Foundation
import SwiftData

@Model
public class PathNode {
    @Attribute(.unique) var rawId: String
    var rawParentId: String
    public var name: String

    public init(
        id: NSFileProviderItemIdentifier = NSFileProviderItemIdentifier(UUID().uuidString),
        parentId: NSFileProviderItemIdentifier,
        name: String
    ) {
        self.rawId = id.rawValue
        self.rawParentId = parentId.rawValue
        self.name = name
    }

    public var id: NSFileProviderItemIdentifier {
        get { NSFileProviderItemIdentifier(rawId) }
        set { rawId = newValue.rawValue }
    }

    public var parentId: NSFileProviderItemIdentifier {
        get { NSFileProviderItemIdentifier(rawParentId) }
        set { rawParentId = newValue.rawValue }
    }
}
