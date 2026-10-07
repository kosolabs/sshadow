import Foundation

extension FileManager {
    public func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
    }

    public func destinationOfSymbolicLink(at url: URL) throws -> String {
        try destinationOfSymbolicLink(atPath: url.path)
    }
    
    public func attributes(of url: URL) throws -> NSDictionary {
        try self.attributesOfItem(atPath: url.path) as NSDictionary
    }

    public func size(of url: URL) throws -> UInt64 {
        try attributes(of: url).fileSize()
    }

    public func totalSize(of url: URL) throws -> UInt64 {
        let attrs = try attributes(of: url)
        guard attrs.fileType() == FileAttributeType.typeDirectory.rawValue
        else {
            return attrs.fileType() == FileAttributeType.typeRegular.rawValue
                ? attrs.fileSize() : 0
        }
        return try contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ).reduce(0) { total, child in
            try total + totalSize(of: child)
        }
    }

    public func permissions(of url: URL) throws -> mode_t {
        UInt16(try attributes(of: url).filePosixPermissions())
    }

    public func modifyDate(of url: URL) throws -> Date {
        guard let date = try attributes(of: url).fileModificationDate() else {
            throw NSError(
                domain: "FileManagerExtensions",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to get modification date for \(url)"
                ]
            )
        }
        return date
    }
}
