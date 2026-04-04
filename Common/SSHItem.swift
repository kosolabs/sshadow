import FileProvider
import Foundation
import SwiftData

@Model
public class SSHItem {
    @Attribute(.unique) public var id: String
    public var parentId: String
    public var name: String

    public init(id: String, parentId: String, name: String) {
        self.id = id
        self.parentId = parentId
        self.name = name
    }

    public var fpItemIdentifier: NSFileProviderItemIdentifier {
        switch id {
        case NSFileProviderItemIdentifier.rootContainer.rawValue:
            return NSFileProviderItemIdentifier.rootContainer
        case NSFileProviderItemIdentifier.trashContainer.rawValue:
            return NSFileProviderItemIdentifier.trashContainer
        case NSFileProviderItemIdentifier.workingSet.rawValue:
            return NSFileProviderItemIdentifier.workingSet
        default:
            return NSFileProviderItemIdentifier(id)
        }
    }
}
