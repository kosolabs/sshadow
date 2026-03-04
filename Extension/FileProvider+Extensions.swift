import FileProvider

extension NSFileProviderItem {
    var desc: String {
        var components: [String] = []
        components.append("id: \(itemIdentifier.desc)")
        components.append("parentId: \(parentItemIdentifier.desc)")
        components.append("filename: \(filename)")

        if let contentType = contentType {
            components.append("contentType: \(contentType)")
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

extension NSFileProviderItemIdentifier {
    var desc: String {
        if self == .rootContainer {
            return "FPItemID.rootContainer"
        }
        if self == .workingSet {
            return "FPItemID.workingSet"
        }
        if self == .trashContainer {
            return "FPItemID.trashContainer"
        }
        return "FPItemID(\(rawValue))"
    }

    var name: String {
        rawValue.split(separator: "/").last.map(String.init) ?? ""
    }

    var parent: NSFileProviderItemIdentifier {
        if self == .rootContainer {
            return .rootContainer
        }

        let parts = rawValue.split(separator: "/").dropLast()
        if parts.isEmpty {
            return .rootContainer
        }

        let parentRawValue = parts.joined(separator: "/")
        return NSFileProviderItemIdentifier(parentRawValue)
    }

    func child(name: String) -> NSFileProviderItemIdentifier {
        if self == .rootContainer {
            return NSFileProviderItemIdentifier(name)
        }

        let childRawValue = rawValue + "/" + name
        return NSFileProviderItemIdentifier(childRawValue)
    }
}

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

extension NSFileProviderItemFields {
    public var desc: String {
        var result: [String] = []
        result.append("rawValue: \(rawValue)")
        for (field, name) in allItemFields where self.contains(field) {
            result.append(name)
        }
        return "FPItemFields(\(result.joined(separator: ", ")))"
    }
}

extension NSFileProviderItemCapabilities {
    var desc: String {
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
    var desc: String {
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
