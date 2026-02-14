import Common
import Foundation

struct TestData {
    static let name = "test"
    static let host = "localhost"
    static let port: UInt16 = 2248
    static let user = NSUserName()
    static let path = "media"
    static let privateKeyURL = URL(filePath: "/tmp/id_ed25519")

    static func getConnectionConfig(
        id: UUID = UUID()
    ) throws -> ConnectionConfig {
        try ConnectionConfig(
            id: id,
            name: name,
            host: host,
            port: port,
            user: user,
            path: path,
            authMethod: .privateKey(
                base64PrivateKey: getBase64PrivateKey(),
                passphrase: nil
            ),
        )
    }
    
    static func getUserInfo(id: UUID = UUID()) throws -> UserInfo {
        try UserInfo(
            id: id,
            name: name,
            host: host,
            port: port,
            user: user,
            path: path,
            authMethod: .privateKey(
                bookmark: privateKeyURL.bookmarkData()
            )
        )
    }

    static func getBase64PrivateKey() throws -> String {
        try Data(contentsOf: privateKeyURL).decoded(as: .utf8)
    }
}
