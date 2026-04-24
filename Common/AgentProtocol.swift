import Foundation
import SwiftLibSSH

@objc public protocol AgentProtocol {
    func perform(_ request: Data, reply: @escaping (Data) -> Void)
}

public enum AgentRequest: Codable {
    case sayHello(name: String)
    case loadConfig(domainID: UUID)
    case attributes(domainID: UUID, itemID: String)
}

public enum AgentResponse: Codable {
    case sayHello(greeting: String)
    case attributes(SFTPAttributes)
    case loadConfig
}

public enum AgentError: Codable, Error {
    case profileNotFound(UUID)
}

public enum AgentResultError: Codable, Error {
    case agent(AgentError)
    case ssh(SSHError)
    case sftp(SFTPError)
    case unknown(domain: String, code: Int, message: String)

    public init(from error: any Error) {
        switch error {
        case let error as AgentError:
            self = .agent(error)
        case let error as SSHError:
            self = .ssh(error)
        case let error as SFTPError:
            self = .sftp(error)
        default:
            let nsError = error as NSError
            self = .unknown(
                domain: nsError.domain,
                code: nsError.code,
                message: nsError.localizedDescription
            )
        }
    }

    public var underlyingError: any Error {
        switch self {
        case .agent(let error): error
        case .ssh(let error): error
        case .sftp(let error): error
        case .unknown(let domain, let code, let message):
            NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}

public enum AgentResult: Codable {
    case success(AgentResponse)
    case failure(AgentResultError)

    public func get() throws -> AgentResponse {
        switch self {
        case .success(let response): return response
        case .failure(let error): throw error.underlyingError
        }
    }
}

public enum AgentCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data)
        throws -> T
    {
        try JSONDecoder().decode(type, from: data)
    }
}
