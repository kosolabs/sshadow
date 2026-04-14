import FileProvider
import Foundation
import SwiftData

@Model
public class SSHChunk {
    var rawItemId: String
    var index: Int

    public init(
        itemId: NSFileProviderItemIdentifier,
        index: Int
    ) {
        self.rawItemId = itemId.rawValue
        self.index = index
    }

    public var itemId: NSFileProviderItemIdentifier {
        get { NSFileProviderItemIdentifier(rawItemId) }
        set { rawItemId = newValue.rawValue }
    }
}
