import SwiftUI
import SwiftData

@Model class ConnectionConfig {
    @Attribute(.unique) var id: UUID
    var host: String
    var port: UInt16?
    var user: String?
    var password: String?
    
    var effectivePort: UInt16 {
        port ?? 22
    }
    
    var effectiveUser: String {
        user ?? NSUserName()
    }
    
    init(id: UUID = UUID(), host: String, port: UInt16? = nil, user: String? = nil, password: String? = nil) {
        self.id = id
        self.host = host
        self.port = port
        self.user = user
        self.password = password
    }
}
