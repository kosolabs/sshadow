import Foundation

extension FileHandle {
    convenience init(for url: URL, mode: mode_t = 0o666) throws {
        let fd = open(url.path(percentEncoded: false), O_WRONLY | O_CREAT, mode)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        self.init(fileDescriptor: fd, closeOnDealloc: true)
    }
}
