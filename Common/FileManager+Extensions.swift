import Foundation

extension FileManager {
    public func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
    }

    public func attributes(of url: URL) throws -> NSDictionary {
        try self.attributesOfItem(atPath: url.path) as NSDictionary
    }

    public func size(of url: URL) throws -> UInt64 {
        try attributes(of: url).fileSize()
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
