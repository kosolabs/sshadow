import Foundation

extension FileManager {
    public func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
    }

    public func destinationOfSymbolicLink(at url: URL) throws -> String {
        try destinationOfSymbolicLink(atPath: url.path)
    }

    public func size(of url: URL) throws -> UInt64 {
        let values = try url.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        )
        if values.isDirectory == true {
            return try contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .isRegularFileKey, .fileSizeKey,
                ]
            ).reduce(0) { total, child in
                try total + size(of: child)
            }
        }
        return values.isRegularFile == true ? UInt64(values.fileSize ?? 0) : 0
    }
}
