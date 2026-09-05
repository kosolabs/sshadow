@_silgen_name("swift_EnumCaseName")
private func _getEnumCaseName<T>(_ value: T) -> UnsafePointer<CChar>?

private func enumCaseName(of value: Any) -> String? {
    guard let cString = _getEnumCaseName(value) else { return nil }
    return String(validatingCString: cString)
}

public protocol PrettyDescribable: CustomStringConvertible {}

extension PrettyDescribable {
    public var description: String {
        let mirror = Mirror(reflecting: self)
        let typeName = String(describing: type(of: self))

        switch mirror.displayStyle {
        case .enum:
            guard let caseName = enumCaseName(of: self) else { return typeName }
            let name = "\(typeName).\(caseName)"
            guard let child = mirror.children.first else { return name }
            return "\(name)(\(formatPayload(child.value)))"
        default:
            let fields = mirror.children.compactMap { label, value -> String? in
                guard let label else { return nil }
                return "\(label): \(formatValue(value))"
            }.joined(separator: ", ")
            return "\(typeName)(\(fields))"
        }
    }
}

private func formatPayload(_ payload: Any) -> String {
    let mirror = Mirror(reflecting: payload)
    guard mirror.displayStyle == .tuple else { return formatValue(payload) }
    return mirror.children.map { label, value in
        guard let label, !label.hasPrefix(".") else {
            return formatValue(value)
        }
        return "\(label): \(formatValue(value))"
    }.joined(separator: ", ")
}

private func formatValue(_ value: Any) -> String {
    guard let value = unwrapOptional(value) else { return "nil" }
    if let string = value as? String {
        return "\"\(string)\""
    }
    return "\(value)"
}

private func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first?.value
}
