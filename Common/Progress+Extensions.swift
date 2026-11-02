import Foundation

extension Progress {
    public var report: String {
        self.localizedAdditionalDescription ?? self.description
    }
}
