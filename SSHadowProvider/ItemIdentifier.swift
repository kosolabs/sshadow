import FileProvider

extension NSFileProviderItemIdentifier {
    func parent() -> NSFileProviderItemIdentifier {
        if self == .rootContainer {
            return .rootContainer
        }
        
        let parts = rawValue.split(separator: "/").dropLast()
        if parts.isEmpty {
            return NSFileProviderItemIdentifier.rootContainer
        }
        
        let parentRawValue = parts.joined(separator: "/")
        return NSFileProviderItemIdentifier(rawValue: parentRawValue)
    }
    
    func child(name: String) -> NSFileProviderItemIdentifier {
        if self == .rootContainer {
            return NSFileProviderItemIdentifier(rawValue: name)
        }
        
        let childRawValue = rawValue + "/" + name
        return NSFileProviderItemIdentifier(rawValue: childRawValue)
    }
    
    func path(base: String) -> String {
        if self == .rootContainer {
            return base
        }
        return base + "/" + rawValue
    }
}
