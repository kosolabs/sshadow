import Foundation
import SwiftLibSSH

public enum OnExists: Codable {
    case fail
    case succeed
}

@objc public protocol AgentProtocol {
    func perform(_ request: Data, reply: @escaping (Data) -> Void)
}

public enum AgentRequest: Codable {
    case name(domainId: UUID, itemId: String)
    case child(
        domainId: UUID,
        parentId: String,
        path: String,
        ifNotExists: DomainDB.OnNotExists
    )
    case parent(domainId: UUID, itemId: String)
    case pathForItem(domainId: UUID, itemId: String)
    case pathForChild(domainId: UUID, name: String, parentId: String)
    case attributes(domainId: UUID, itemId: String)
    case setAttributes(
        domainId: UUID,
        itemId: String,
        permissions: mode_t?,
        accessTime: Date?,
        modifyTime: Date?
    )
    case createDirectory(
        domainId: UUID,
        itemId: String,
        mode: mode_t,
        ifExists: OnExists
    )
}

public enum AgentResponse: Codable {
    case name(name: String)
    case child(itemId: String)
    case parent(itemId: String)
    case path(path: String)
    case attributes(SFTPAttributes)
    case setAttributes
    case createDirectory
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
