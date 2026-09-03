import Foundation

public extension Progress {
    var report: String {
        self.localizedAdditionalDescription ?? self.description
    }
}
