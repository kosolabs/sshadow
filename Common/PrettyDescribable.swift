public protocol PrettyDescribable: CustomStringConvertible {}

extension PrettyDescribable {
    public var description: String {
        let mirror = Mirror(reflecting: self)
        let typeName = String(describing: type(of: self))

        switch mirror.displayStyle {
        case .enum:
            guard let child = mirror.children.first, let label = child.label
            else {
                return typeName
            }
            return "\(label)(\(child.value))"
        default:
            let fields = mirror.children.compactMap { label, value -> String? in
                guard let label else { return nil }
                return "\(label): \(value)"
            }.joined(separator: ", ")
            return "\(typeName)(\(fields))"
        }
    }
}
