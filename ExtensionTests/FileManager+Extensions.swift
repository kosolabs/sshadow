import Foundation

extension FileManager {
    func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
    }
    
    func permissions(of url: URL) throws -> mode_t {
        let attributes = try self.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? mode_t else {
            throw NSError(
                domain: "FileManagerExtensions",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to get permissions for \(url)"
                ]
            )
        }
        return permissions
    }

    func modifyDate(of url: URL) throws -> Date {
        let attributes = try self.attributesOfItem(atPath: url.path)
        guard let date = attributes[.modificationDate] as? Date else {
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
