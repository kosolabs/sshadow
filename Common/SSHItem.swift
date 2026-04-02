import Foundation
import SwiftData

@Model
public class SSHItem {
    @Attribute(.unique) public var id: UUID
    public var parentId: UUID
    public var name: String

    public init(id: UUID, parentId: UUID, name: String) {
        self.id = id
        self.parentId = parentId
        self.name = name
    }
}
