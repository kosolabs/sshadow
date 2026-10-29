import AppKit

extension NSPasteboard {
    func copy(_ string: String) {
        clearContents()
        setString(string, forType: .string)
    }
}
