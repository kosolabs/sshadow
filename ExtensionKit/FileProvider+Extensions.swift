import Common
import FileProvider

extension NSFileProviderItem {
    public var id: NSFileProviderItemIdentifier {
        itemIdentifier
    }

    public var parentId: NSFileProviderItemIdentifier {
        parentItemIdentifier
    }

    public var desc: String {
        var components: [String] = []
        components.append("id: \(id.desc)")
        components.append("parentId: \(parentId.desc)")
        components.append("filename: \(filename)")

        if let contentType = contentType {
            components.append("contentType: \(contentType)")
        }
        if let symlinkTargetPath = symlinkTargetPath ?? nil {
            components.append(
                "target: \(symlinkTargetPath)"
            )
        }
        if let typeAndCreator = typeAndCreator {
            if typeAndCreator.type != 0 || typeAndCreator.creator != 0 {
                components.append("typeAndCreator: \(typeAndCreator)")
            }
        }
        if let capabilities = capabilities {
            components.append("capabilities: \(capabilities.desc)")
        }
        if let fileSystemFlags = fileSystemFlags {
            components.append("fileSystemFlags: \(fileSystemFlags.desc)")
        }
        if let s = documentSize, let size = s {
            components.append("size: \(size)")
        }
        if let c = childItemCount, let children = c {
            components.append("children: \(children)")
        }
        if let ct = creationDate, let createTime = ct {
            components.append("createTime: \(createTime)")
        }
        if let mt = contentModificationDate, let modifyTime = mt {
            components.append("modifyTime: \(modifyTime)")
        }
        if let at = lastUsedDate, let accessTime = at {
            components.append("accessTime: \(accessTime)")
        }
        if let extendedAttributes = extendedAttributes {
            if !extendedAttributes.isEmpty {
                components.append("extendedAttributes: \(extendedAttributes)")
            }
        }
        if isUploaded == true {
            components.append("uploaded")
        }
        if isUploading == true {
            components.append("uploading")
        }
        if let e = uploadingError, let error = e {
            components.append("uploadingError: \(error)")
        }
        if isDownloaded == true {
            components.append("downloaded")
        }
        if isDownloading == true {
            components.append("downloading")
        }
        if let e = downloadingError, let error = e {
            components.append("downloadingError: \(error)")
        }
        if isMostRecentVersionDownloaded == true {
            components.append("mostRecentVersionDownloaded")
        }
        if isShared == true {
            components.append("shared")
        }
        if isSharedByCurrentUser == true {
            components.append("sharedByCurrentUser")
        }
        if let o = ownerNameComponents, let owner = o {
            components.append("owner: \(owner)")
        }
        if let e = mostRecentEditorNameComponents, let editor = e {
            components.append("editor: \(editor)")
        }
        if let ui = userInfo, let userInfo = ui {
            components.append("userInfo: \(userInfo)")
        }
        return "FPItem(\(components.joined(separator: ", ")))"
    }
}

public let allItemFields: [(NSFileProviderItemFields, String)] = [
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

extension NSFileProviderItemFields {
    public static let nameFields: NSFileProviderItemFields = [
        .parentItemIdentifier, .filename,
    ]

    public static let attrFields: NSFileProviderItemFields = [
        .creationDate, .contentModificationDate, .lastUsedDate,
        .fileSystemFlags, .typeAndCreator,
    ]

    public static let writeFields: NSFileProviderItemFields = [
        .contents
    ]

    public var desc: String {
        var result: [String] = []
        result.append("rawValue: \(rawValue)")
        for (field, name) in allItemFields where self.contains(field) {
            result.append(name)
        }
        return "FPItemFields(\(result.joined(separator: ", ")))"
    }

    public func intersects(with members: NSFileProviderItemFields) -> Bool {
        return !intersection(members).isEmpty
    }
}

extension NSFileProviderItemCapabilities {
    public var desc: String {
        var result = [String]()
        result.append("rawValue: \(rawValue)")
        if contains(.allowsReading) {
            result.append("reading")
        }
        if contains(.allowsWriting) {
            result.append("writing")
        }
        if contains(.allowsReparenting) {
            result.append("reparenting")
        }
        if contains(.allowsRenaming) {
            result.append("renaming")
        }
        if contains(.allowsTrashing) {
            result.append("trashing")
        }
        if contains(.allowsDeleting) {
            result.append("deleting")
        }
        if contains(.allowsExcludingFromSync) {
            result.append("noSync")
        }
        return "FPItemCapabilities(\(result.joined(separator: ", ")))"
    }
}

extension NSFileProviderFileSystemFlags {
    public init(mode: mode_t) {
        var flags: NSFileProviderFileSystemFlags = []
        if mode & S_IRUSR != 0 {
            flags.insert(.userReadable)
        }
        if mode & S_IWUSR != 0 {
            flags.insert(.userWritable)
        }
        if mode & S_IXUSR != 0 {
            flags.insert(.userExecutable)
        }
        self = flags
    }

    public var permissions: mode_t {
        var mode: mode_t = 0
        if contains(.userReadable) {
            mode |= S_IRUSR
        }
        if contains(.userWritable) {
            mode |= S_IWUSR
        }
        if contains(.userExecutable) {
            mode |= S_IXUSR
        }
        return mode
    }

    public var desc: String {
        var flags = [String]()
        flags.append("rawValue: \(rawValue)")
        if contains(.userExecutable) {
            flags.append("executable")
        }
        if contains(.userReadable) {
            flags.append("readable")
        }
        if contains(.userWritable) {
            flags.append("writable")
        }
        if contains(.hidden) {
            flags.append("hidden")
        }
        if contains(.pathExtensionHidden) {
            flags.append("pathExtensionHidden")
        }
        return "FPFileSystemFlags(\(flags.joined(separator: ", ")))"
    }
}
