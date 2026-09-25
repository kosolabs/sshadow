import Common
import FileProvider
import UniformTypeIdentifiers

enum TemplateKind: Message, PrettyDescribable {
    case file
    case folder
    case symlink(target: String)
    case package
    case unknown

    init(_ item: NSFileProviderItem) {
        guard let type = item.contentType else {
            self = .unknown
            return
        }

        if type.conforms(to: .symbolicLink) {
            guard let target = item.symlinkTargetPath ?? nil else {
                self = .unknown
                return
            }
            self = .symlink(target: target)
        } else if type.conforms(to: .package) {
            self = .package
        } else if type.conforms(to: .directory) {
            self = .folder
        } else if type.conforms(to: .data) {
            self = .file
        } else {
            self = .unknown
        }
    }
}
