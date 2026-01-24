import Foundation
import SwiftLibSSH

enum ConnectionTestStatus: Equatable {
    case notStarted
    case testing
    case success
    case invalidConfig(String)
    case other(String)
}

protocol ConnectionTester {
    func test(host: String, port: UInt16, user: String, password: String) async -> ConnectionTestStatus
}

struct DefaultConnectionTester: ConnectionTester {
    func test(host: String, port: UInt16, user: String, password: String) async -> ConnectionTestStatus {
        do {
            return try await SSHClient.withAuthenticatedClient(
                host: host, port: port, user: user, password: password
            ) { client in
                _ = try await client.execute("whoami")
                    .stdout.decoded(as: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .success
            }
        } catch {
            return .other("\(error)")
        }
    }
}

extension Data {
  func decoded(as encoding: String.Encoding) throws -> String {
    guard let str = String(data: self, encoding: encoding) else {
      throw SSHClientError.decodeFailed("Failed to decode data as \(encoding)")
    }
    return str
  }
}
