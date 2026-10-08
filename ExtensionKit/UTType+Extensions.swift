import Common
import UniformTypeIdentifiers

extension UTType {
    init(for ext: String, conformingTo type: UTType) {
        self = UTType(filenameExtension: ext, conformingTo: type) ?? type
    }

    init(file name: String) {
        let ext = (name as NSString).pathExtension
        self.init(for: ext, conformingTo: .data)
    }

    init(package name: String) {
        let ext = (name as NSString).pathExtension
        self.init(for: ext, conformingTo: .package)
    }
}
