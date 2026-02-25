import Common
import FileProvider

let allItemFields: [(NSFileProviderItemFields, String)] = [
    (.contents, "contents"),
    (.filename, "filename"),
    (.parentItemIdentifier, "parentItemIdentifier"),
    (.lastUsedDate, "lastUsedDate"),
    (.tagData, "tagData"),
    (.favoriteRank, "favoriteRank"),
    (.creationDate, "creationDate"),
    (.contentModificationDate, "contentModificationDate"),
    (.fileSystemFlags, "fileSystemFlags"),
    (.extendedAttributes, "extendedAttributes"),
    (.typeAndCreator, "typeAndCreator"),
]

extension NSFileProviderItemFields: @retroactive CustomStringConvertible {
    public var description: String {
        var result: [String] = []
        for (field, name) in allItemFields where self.contains(field) {
            result.append(name)
        }
        return result.joined(separator: ", ")
    }
}
