import SwiftUI
import SwiftData

@Model class ConnectionConfig {
    @Attribute(.unique) var id: UUID
    var host: String
    var port: UInt16?
    var user: String?
    var password: String?
    var path: String?
    
    var effectivePort: UInt16 {
        port ?? 22
    }
    
    var effectiveUser: String {
        user ?? NSUserName()
    }
    
    var effectivePath: String {
        path ?? "~"
    }
    
    init(
        id: UUID = UUID(),
        host: String, port: UInt16? = nil,
        user: String? = nil, password: String? = nil,
        path: String? = nil
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.path = path
    }
    
    var description: String {
        var result = "\(effectiveUser)@\(host)"
        if let port = port {
            result += ":\(port)"
        }
        if let path = path {
            result += ":\(path)"
        }
        return result
    }
}
