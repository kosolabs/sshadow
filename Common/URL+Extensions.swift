import Foundation

private let shellSafe = CharacterSet.alphanumerics.union(
    CharacterSet(charactersIn: "@.:/_-+,%")
)

extension URL {
    public var shellEscapedPath: String {
        var result = ""
        for scalar in path(percentEncoded: false).unicodeScalars {
            if shellSafe.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result += "\\"
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
