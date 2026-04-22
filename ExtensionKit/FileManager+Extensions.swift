import Foundation

extension FileManager {
    func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
    }
    
    func attributes(of url: URL) throws -> NSDictionary {
        try self.attributesOfItem(atPath: url.path) as NSDictionary
    }

    func size(of url: URL) throws -> UInt64 {
        try attributes(of: url).fileSize()
    }
    
    func permissions(of url: URL) throws -> mode_t {
        UInt16(try attributes(of: url).filePosixPermissions())
    }

    func modifyDate(of url: URL) throws -> Date {
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
