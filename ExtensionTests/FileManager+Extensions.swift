import Foundation

extension FileManager {
    func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
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
